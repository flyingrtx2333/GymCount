import Combine
import Foundation
import HealthKit
import os

/// Owns one whole-training HealthKit session. Missing samples stay missing.
@MainActor
final class LiveWorkoutMetrics: NSObject, ObservableObject {
    struct HeartRatePoint: Equatable, Sendable {
        let date: Date
        let beatsPerMinute: Double
    }

    struct Result: Equatable, Sendable {
        let workoutUUID: UUID?
        let activeEnergyKilocalories: Double?
        let averageHeartRate: Double?
        let maximumHeartRate: Double?
        let heartRateSamples: [HeartRatePoint]
    }

    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var isFinishing = false
    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var activeEnergyKilocalories: Double?
    @Published private(set) var errorMessage: String?
    private(set) var workoutID: UUID?

    private let healthStore: HKHealthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isStarting = false
    private var generation = UUID()
    private var startedAt: Date?
    private var endedAt: Date?
    private var averageHeartRate: Double?
    private var maximumHeartRate: Double?
    private var heartRateSamples: [HeartRatePoint] = []
    private var finishedResult: Result?
    private var finishTask: Task<Result, Error>?
    private var stopContinuation: CheckedContinuation<Void, Error>?
    private var stopTimeout: Task<Void, Never>?
    private let heartRateType = HKQuantityType(.heartRate)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
    private nonisolated static let maximumHeartRatePoints = 4_096
    private let saveLog = Logger(subsystem: "com.flyingrtx.GymCount.watchkitapp", category: "WorkoutSave")

    init(healthStore: HKHealthStore) { self.healthStore = healthStore }

    func begin(id: UUID, startDate: Date) async throws {
        guard !isStarting, session == nil, !isFinishing else {
            throw failure("训练正在进行中")
        }
        isStarting = true
        let token = UUID()
        generation = token
        workoutID = id
        errorMessage = nil
        finishedResult = nil
        heartRateSamples = []
        currentHeartRate = nil
        averageHeartRate = nil
        maximumHeartRate = nil
        activeEnergyKilocalories = nil
        startedAt = startDate
        endedAt = nil
        defer { if generation == token { isStarting = false } }
        do {
            guard HKHealthStore.isHealthDataAvailable() else { throw failure("健康数据暂不可用") }
            try await healthStore.requestAuthorization(toShare: [.workoutType(), energyType],
                read: [.workoutType(), energyType, heartRateType])
            guard generation == token else { throw CancellationError() }
            guard healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
                throw failure("请先允许写入体能训练")
            }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            self.session = session
            self.builder = builder
            session.delegate = self
            builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                workoutConfiguration: configuration)
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: "com.flyingrtx.GymCount.workout.\(id.uuidString)",
                HKMetadataKeySyncVersion: 1,
                "app_name": "GymCount",
                "whole_workout": true
            ])
            guard generation == token else { throw CancellationError() }
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            guard generation == token, self.session === session else { throw CancellationError() }
            isRunning = true
        } catch {
            if generation == token {
                errorMessage = error.localizedDescription
                releaseSession(discard: true)
            }
            throw error
        }
    }

    func pause() {
        guard isRunning, !isPaused, !isFinishing else { return }
        session?.pause()
        isPaused = true
    }

    func resume() {
        guard isRunning, isPaused, !isFinishing else { return }
        session?.resume()
        isPaused = false
    }

    /// Repeated save taps await the same HealthKit write.
    func finish(at endDate: Date) async throws -> Result {
        if let finishedResult { return finishedResult }
        if let finishTask { return try await finishTask.value }
        guard let session, let builder, !isStarting else {
            throw failure(errorMessage ?? "没有进行中的健康训练")
        }
        guard let startedAt, endDate >= startedAt else { throw failure("训练时间无效") }
        endedAt = endDate
        isFinishing = true
        let task = Task { @MainActor in
            let started = ProcessInfo.processInfo.systemUptime
            var phase = "health_stop"
            var phaseStarted = started
            do {
                try await waitForSessionStop(session, at: endDate)
                saveLog.notice("phase=health_stop seconds=\(ProcessInfo.processInfo.systemUptime - phaseStarted)")
                phase = "health_collection"
                phaseStarted = ProcessInfo.processInfo.systemUptime
                try await builder.endCollection(at: endDate)
                saveLog.notice("phase=health_collection seconds=\(ProcessInfo.processInfo.systemUptime - phaseStarted)")
                collectStatistics(from: builder)
                phase = "health_commit"
                phaseStarted = ProcessInfo.processInfo.systemUptime
                guard let workout = try await builder.finishWorkout() else {
                    throw failure("健康训练保存失败，请重试")
                }
                saveLog.notice("phase=health_commit seconds=\(ProcessInfo.processInfo.systemUptime - phaseStarted)")
                // The live builder already supplied measured statistics and chart points.
                let result = snapshot(workoutUUID: workout.uuid)
                finishedResult = result
                releaseSession(discard: false)
                saveLog.notice("phase=health_total seconds=\(ProcessInfo.processInfo.systemUptime - started)")
                return result
            } catch {
                let failure = error as NSError
                saveLog.error("phase=\(phase, privacy: .public) seconds=\(ProcessInfo.processInfo.systemUptime - phaseStarted) error_domain=\(failure.domain, privacy: .public) error_code=\(failure.code)")
                errorMessage = error.localizedDescription
                releaseSession(discard: true)
                throw error
            }
        }
        finishTask = task
        defer {
            finishTask = nil
            isFinishing = false
        }
        return try await task.value
    }

    func snapshot() -> Result { finishedResult ?? snapshot(workoutUUID: nil) }

    func discard(id: UUID? = nil) {
        guard !isFinishing, id == nil || id == workoutID else { return }
        generation = UUID()
        isStarting = false
        releaseSession(discard: true)
        finishedResult = nil
        workoutID = nil
        startedAt = nil
        endedAt = nil
        heartRateSamples = []
        currentHeartRate = nil
        averageHeartRate = nil
        maximumHeartRate = nil
        activeEnergyKilocalories = nil
        errorMessage = nil
    }

    private func snapshot(workoutUUID: UUID?) -> Result {
        Result(workoutUUID: workoutUUID, activeEnergyKilocalories: activeEnergyKilocalories,
            averageHeartRate: averageHeartRate, maximumHeartRate: maximumHeartRate,
            heartRateSamples: heartRateSamples.filter {
                $0.date >= (startedAt ?? .distantPast) && $0.date <= (endedAt ?? .distantFuture)
            })
    }

    private func waitForSessionStop(_ session: HKWorkoutSession, at endDate: Date) async throws {
        if session.state == .stopped || session.state == .ended { return }
        try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            stopTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.completeStopWait(throwing: self?.failure("健康训练结束超时，请重试"))
            }
            session.stopActivity(with: endDate)
        }
    }

    private func completeStopWait(throwing error: Error? = nil) {
        stopTimeout?.cancel()
        stopTimeout = nil
        let continuation = stopContinuation
        stopContinuation = nil
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
    }

    private func releaseSession(discard: Bool) {
        session?.delegate = nil
        builder?.delegate = nil
        if session?.state != .ended { session?.end() }
        if discard { builder?.discardWorkout() }
        session = nil
        builder = nil
        isRunning = false
        isPaused = false
    }

    private func collectStatistics(from builder: HKLiveWorkoutBuilder) {
        if let stats = builder.statistics(for: energyType),
           let value = stats.sumQuantity()?.doubleValue(for: .kilocalorie()),
           value.isFinite, value >= 0 {
            activeEnergyKilocalories = value
        }
        guard let stats = builder.statistics(for: heartRateType) else { return }
        averageHeartRate = positive(stats.averageQuantity()?.doubleValue(for: heartRateUnit))
        maximumHeartRate = positive(stats.maximumQuantity()?.doubleValue(for: heartRateUnit))
        guard let value = positive(stats.mostRecentQuantity()?.doubleValue(for: heartRateUnit)),
              let date = stats.mostRecentQuantityDateInterval()?.end else { return }
        currentHeartRate = value
        let point = HeartRatePoint(date: date, beatsPerMinute: value)
        if let last = heartRateSamples.last, last.date == date {
            heartRateSamples[heartRateSamples.count - 1] = point
        } else if heartRateSamples.last.map({ $0.date < date }) ?? true {
            heartRateSamples.append(point)
            if heartRateSamples.count > Self.maximumHeartRatePoints {
                heartRateSamples = compactedHeartRate(heartRateSamples,
                    limit: Self.maximumHeartRatePoints / 2)
            }
        }
    }

    // Keep original observations, including both endpoints. Averages/maximums come
    // directly from HealthKit statistics and never from this compact chart trace.
    private func compactedHeartRate(_ points: [HeartRatePoint],
        limit: Int = LiveWorkoutMetrics.maximumHeartRatePoints) -> [HeartRatePoint] {
        let sorted = points.sorted { $0.date < $1.date }
        var unique: [HeartRatePoint] = []
        for point in sorted {
            if unique.last?.date == point.date { unique[unique.count - 1] = point }
            else { unique.append(point) }
        }
        guard unique.count > limit else { return unique }
        return (0..<limit).map { index in
            unique[index * (unique.count - 1) / (limit - 1)]
        }
    }

    private func positive(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && (1...300).contains($0) ? $0 : nil }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "PowerReps.LiveWorkout", code: 1,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(message, comment: "")])
    }
}

extension LiveWorkoutMetrics: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            switch toState {
            case .running: isPaused = false
            case .paused: isPaused = true
            case .stopped:
                if isFinishing { completeStopWait() }
            case .ended:
                if isFinishing { completeStopWait() }
                else {
                    errorMessage = String(localized: "健康训练已中断")
                    releaseSession(discard: true)
                }
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            errorMessage = error.localizedDescription
            completeStopWait(throwing: error)
            releaseSession(discard: true)
        }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            collectStatistics(from: workoutBuilder)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
