import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published private(set) var isSyncing = false
    @Published private(set) var syncMessage: String?
    private var pending: [UUID: Task<Void, Error>] = [:]
    private var syncingBatch = false
    @MainActor lazy var liveWorkout = LiveWorkoutMetrics(healthStore: healthStore)

    private init() { checkAuthorizationStatus() }

    func checkAuthorizationStatus() {
        let status = HKHealthStore.isHealthDataAvailable()
            ? healthStore.authorizationStatus(for: .workoutType()) : .notDetermined
        authorizationStatus = status
        isAuthorized = status == .sharingAuthorized
    }

    func refreshAuthorizationStatus() { checkAuthorizationStatus() }
    func debugAuthorizationStatus() { print("HealthKit: \(authorizationStatus.rawValue)") }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate)!
        do {
            try await healthStore.requestAuthorization(toShare: [.workoutType(), energy], read: [.workoutType(), energy, bodyMass, heartRate])
        } catch {
            await MainActor.run { syncMessage = String(localized: "健康权限请求失败，请稍后重试") }
        }
        await MainActor.run { checkAuthorizationStatus() }
    }

    @MainActor
    func getUserBodyWeight() async -> Double {
        let fallback = DataManager.shared.settings.userBodyWeight
        let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        // Read permission is private; sharing authorization cannot tell us whether reads are allowed.
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                let weight = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: weight.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? fallback)
            }
            healthStore.execute(query)
        }
    }

    @MainActor @discardableResult
    func saveWorkoutToHealthKit(_ history: WorkoutHistory) async -> Bool {
        // Whole-training energy is collected by HKLiveWorkoutBuilder. Never re-export it
        // through the legacy calorie estimator, even if HealthKit read access is denied.
        if let report = history.workoutReport { return report.healthWorkoutID != nil }
        if let task = pending[history.id] { return (try? await task.value) != nil }
        checkAuthorizationStatus()
        guard isAuthorized else {
            syncMessage = String(localized: "请先允许写入体能训练")
            return false
        }
        let task = Task { try await writeWorkout(history) }
        pending[history.id] = task
        isSyncing = true
        defer {
            pending[history.id] = nil
            isSyncing = syncingBatch || !pending.isEmpty
        }
        do {
            try await task.value
            if !syncingBatch { syncMessage = String(localized: "已同步到健康") }
            return true
        } catch {
            syncMessage = String(localized: "健康同步失败，请重试")
            return false
        }
    }

    @MainActor
    func syncWorkoutHistory(_ history: [WorkoutHistory]) async {
        guard !syncingBatch else { return }
        syncingBatch = true; isSyncing = true
        syncMessage = String(localized: "正在同步到健康…")
        var failed = 0
        for workout in history {
            if !(await saveWorkoutToHealthKit(workout)) { failed += 1 }
        }
        syncingBatch = false; isSyncing = !pending.isEmpty
        if failed > 0 { syncMessage = String(localized: "\(failed) 条记录未同步，请重试") }
        else { syncMessage = String(localized: "已同步 \(history.count) 条记录") }
    }

    private static func syncIdentifier(_ id: UUID, energy: Bool = false) -> String {
        "com.flyingrtx.GymCount.\(energy ? "energy" : "workout").\(id.uuidString)"
    }

    private func samples(_ type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            healthStore.execute(query)
        }
    }

    private func existingWorkout(_ history: WorkoutHistory) async throws -> HKWorkout? {
        let identifier = Self.syncIdentifier(history.id)
        let stable = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier])
        let owned = HKQuery.predicateForObjects(from: HKSource.default())
        let interval = HKQuery.predicateForSamples(withStart: history.date.addingTimeInterval(-1), end: history.date.addingTimeInterval(1), options: .strictStartDate)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [owned, NSCompoundPredicate(orPredicateWithSubpredicates: [stable, interval])])
        let workouts = try await samples(.workoutType(), predicate: predicate).compactMap { $0 as? HKWorkout }
        if let existing = workouts.first(where: { $0.metadata?[HKMetadataKeySyncIdentifier] as? String == identifier }) { return existing }
        // Preserve exact app-owned exports from releases that predate stable identifiers.
        return workouts.first {
            $0.metadata?[HKMetadataKeySyncIdentifier] == nil &&
            abs($0.startDate.timeIntervalSince(history.date)) < 0.001 && abs($0.duration - history.duration) < 0.001 &&
            $0.metadata?["exercise_type"] as? String == history.exerciseType.rawValue &&
            ($0.metadata?["total_reps"] as? NSNumber)?.intValue == history.totalReps &&
            ($0.metadata?["max_weight"] as? NSNumber)?.doubleValue == history.maxWeight
        }
    }

    @MainActor
    private func writeWorkout(_ history: WorkoutHistory) async throws {
        let existing = try await existingWorkout(history)
        // The live builder already persisted the workout and its real energy samples.
        if (existing?.metadata?["whole_workout"] as? NSNumber)?.boolValue == true { return }
        let workout: HKWorkout
        if let existing { workout = existing }
        else {
            let bodyWeight = await getUserBodyWeight()
            let calories = calculateEstimatedCalories(reps: history.totalReps, weight: history.maxWeight, bodyWeight: bodyWeight, duration: history.duration)
            workout = HKWorkout(activityType: mapToHKWorkoutType(history.exerciseType), start: history.date,
                end: history.date.addingTimeInterval(history.duration), duration: history.duration,
                totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: calories), totalDistance: nil,
                metadata: [HKMetadataKeySyncIdentifier: Self.syncIdentifier(history.id), HKMetadataKeySyncVersion: 1,
                    "app_name": "GymCount", "exercise_type": history.exerciseType.rawValue,
                    "total_reps": history.totalReps, "max_weight": history.maxWeight])
            try await healthStore.save(workout)
        }
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let identifier = Self.syncIdentifier(history.id, energy: true)
        let energyPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier]),
                HKQuery.predicateForObjects(withMetadataKey: "HKWorkoutActivityID", allowedValues: [workout.uuid.uuidString])])])
        let existingEnergy = try await samples(energyType, predicate: energyPredicate)
        if let sample = existingEnergy.first {
            try await healthStore.addSamples([sample], to: workout)
        } else {
            let energy = HKQuantitySample(type: energyType,
                quantity: workout.totalEnergyBurned ?? HKQuantity(unit: .kilocalorie(), doubleValue: 0),
                start: workout.startDate, end: workout.endDate, metadata: [
                    HKMetadataKeySyncIdentifier: identifier, HKMetadataKeySyncVersion: 1,
                    "HKWorkoutActivityID": workout.uuid.uuidString])
            try await healthStore.addSamples([energy], to: workout)
        }
    }

    private func calculateEstimatedCalories(reps: Int, weight: Double, bodyWeight: Double, duration: TimeInterval) -> Double {
        var met = 5.0
        met += (weight / bodyWeight) * 1.5
        met += Double(reps) / 20.0
        met = min(max(met, 5.0), 9.0)
        let durationHours = duration / 3600.0
        return max(met * bodyWeight * durationHours, 0.5)
    }

    private func mapToHKWorkoutType(_ exercise: ExerciseType) -> HKWorkoutActivityType {
        switch exercise {
        case .benchPress, .squat, .deadlift, .overheadPress, .barbellRow, .bicepCurl: return .traditionalStrengthTraining
        }
    }
}
