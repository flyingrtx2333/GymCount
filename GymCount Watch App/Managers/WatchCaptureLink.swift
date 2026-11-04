#if DEBUG || GYMCOUNT_CAPTURE
import Foundation
import Combine
import WatchConnectivity
import HealthKit
import WatchKit
import OSLog

@MainActor
struct CaptureHealthAuthorization {
    var available: () -> Bool
    var status: () -> HKAuthorizationStatus
    var requestStatus: () async throws -> HKAuthorizationRequestStatus
    var request: () async throws -> Void

    static func live(_ health: HKHealthStore) -> Self {
        Self(available: { HKHealthStore.isHealthDataAvailable() },
             status: { health.authorizationStatus(for: HKObjectType.workoutType()) },
             requestStatus: { try await health.statusForAuthorizationRequest(toShare: [HKObjectType.workoutType()], read: []) },
             request: { try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) })
    }
}

@MainActor
final class WatchCaptureLink: NSObject, ObservableObject, WCSessionDelegate, HKWorkoutSessionDelegate {
    static let shared = WatchCaptureLink(activateConnectivity: true)
    @Published var showingCapture = false
    @Published private(set) var requestedExercise = "squat"
    @Published var remoteSession = false
    @Published var showingPhoneReview = false
    @Published var requestingPhone = false
    @Published private(set) var startingCapture = false
    @Published var message = "" {
        didSet { CollectionStore.shared.message = message }
    }
    @Published var authorizing = false
    @Published private(set) var needsAuthorization = true
    @Published var showingAuthorizationHelp = false
    @Published private(set) var authorizationMessage = ""
    private let health = HKHealthStore()
    private let authorization: CaptureHealthAuthorization
    private let authorizationLog = Logger(subsystem: "com.flyingrtx.GymCount.watchkitapp", category: "CaptureAuthorization")
    private let captureLog = Logger(subsystem: "com.flyingrtx.GymCount.watchkitapp", category: "CaptureLifecycle")
    private let allowsAutomaticAuthorization: Bool
    private var workout: HKWorkoutSession?
    private var pendingStandaloneStart: UUID?
    var isCaptureWorkoutRunning: Bool { workout?.state == .running }
    private var activeID: UUID?
    private var timer: Timer?
    private var lastPublishedStatus: NSDictionary?
    private var sampleOrigin: Double?
    private var completedFiles: [UUID: URL] = [:]
    private var phoneRequestID: UUID?
    private var attemptedInitialAuthorization = false
    private var submittedWorkouts: Set<UUID> = []
    private var submittedTimelines: Set<UUID> = []
    private var preparingLegacyTimelines = false
    private var preparedLegacyTimelines = false
    private var timelineReadFailed = false
    private var timelineRetries: [UUID: Task<Void, Never>] = [:]
    private var timelineAttempts: [UUID: Int] = [:]
    private var reportSensorIndex: [UUID: [UUID]] = [:]
    private var indexedReportIDs: Set<UUID>?
    private var reportSensorScanTask: Task<Void, Never>?
    private var reportSensorScanGeneration = UUID()
    private var reportSensorSyncing = false
    private var reportSensorSyncRequested = false
    private var reportSensorReadFailed = false
    private var failedReportSensorTransfers: Set<String> = []
    private var submittedReportSensors: Set<String> = []
    private var reportSensorAttempts: [String: Int] = [:]
    private var reportSensorRetries: [String: Task<Void, Never>] = [:]

    init(activateConnectivity: Bool, authorization: CaptureHealthAuthorization? = nil) {
        self.authorization = authorization ?? .live(health)
        allowsAutomaticAuthorization = activateConnectivity
        super.init()
        refreshAuthorization()
        if activateConnectivity && WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in if activationState == .activated { self.syncWorkouts(retry: true) } }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in if session.isReachable { self.syncWorkouts(retry: true) } }
    }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in
            guard userInfoTransfer.userInfo["kind"] as? String == WorkoutSync.batchKind else { return }
            // A transport completion is not a persisted-app receipt. Keep these
            // IDs submitted until receipt or an explicit foreground retry.
            if error == nil { self.syncWorkouts() }
        }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let metadata = fileTransfer.file.metadata ?? [:]
        if metadata["kind"] as? String == WorkoutReportSensors.fileKind,
           let text = metadata["id"] as? String, let id = UUID(uuidString: text),
           let parentText = metadata["workout_id"] as? String, let parent = UUID(uuidString: parentText),
           let receiver = metadata["receiver_id"] as? String {
            Task { @MainActor [weak self] in
                guard let self, self.acceptsReportSensors,
                      receiver == UserDefaults.standard.string(forKey: "workoutSync.receiver"),
                      DataManager.shared.workoutHistory.contains(where: { $0.id == parent }) else { return }
                let key = self.reportSensorKey(parent, id)
                guard !(UserDefaults.standard.stringArray(forKey: "reportSensorSync.received") ?? []).contains(key) else { return }
                if error != nil { self.message = String(localized: "时间轴同步失败，将自动重试") }
                self.scheduleReportSensorRetry(workoutID: parent, segmentID: id, receiver: receiver)
                self.syncReportSensors()
            }
            return
        }
        if metadata["kind"] as? String == WorkoutSync.reportFileKind,
           let text = metadata["id"] as? String, let id = UUID(uuidString: text) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let receiver = metadata["receiver_id"] as? String,
                      receiver == UserDefaults.standard.string(forKey: "workoutSync.receiver"),
                      self.acceptsWorkoutReports else {
                    self.syncWorkouts()
                    return
                }
                if (UserDefaults.standard.stringArray(forKey: "workoutSync.received") ?? []).contains(id.uuidString) {
                    try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
                    self.syncWorkouts()
                    return
                }
                if error != nil { self.submittedWorkouts.remove(id); self.message = String(localized: "训练报告同步失败，请重试") }
                // Receipt, rather than file delivery, confirms durable phone storage.
                if error == nil {
                    self.scheduleWorkoutReceiptRetry([id])
                    self.syncWorkouts()
                }
            }
            return
        }
        guard metadata["kind"] as? String == WorkoutTimeline.fileKind,
              let text = metadata["id"] as? String, let id = UUID(uuidString: text) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let defaults = UserDefaults.standard
            let receiver = defaults.string(forKey: "workoutSync.receiver")
            if let expected = metadata["receiver_id"] as? String, expected != receiver { return }
            guard DataManager.shared.workoutHistory.contains(where: { $0.id == id }),
                  !(defaults.stringArray(forKey: "timelineSync.received") ?? []).contains(id.uuidString) else { return }
            if error != nil { self.message = String(localized: "时间轴同步失败，将自动重试") }
            // Delivery is not an app receipt. A failed phone write or a lost
            // receipt leaves this immutable file queued for a bounded retry.
            self.syncWorkoutTimelines()
            self.timelineRetries[id]?.cancel()
            self.timelineRetries[id] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self,
                      UserDefaults.standard.string(forKey: "workoutSync.receiver") == receiver else { return }
                self.timelineRetries.removeValue(forKey: id)
                guard (self.timelineAttempts[id] ?? 0) < 3 else {
                    self.message = String(localized: "时间轴尚未同步，请重试")
                    return
                }
                self.submittedTimelines.remove(id)
                self.syncWorkoutTimelines()
            }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Complete the app's receipt handling before WCSession drains this item.
        if Thread.isMainThread {
            MainActor.assumeIsolated { _ = self.handleWorkoutSync(userInfo) }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { _ = self.handleWorkoutSync(userInfo) } }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if self.handleWorkoutSync(message) { return }
            #if DEBUG
            guard message["command"] as? String == "feedback" else { return }
            if self.showingCapture || (DataManager.shared.currentSession == nil && !CollectionStore.shared.recording && CollectionStore.shared.draft == nil) {
                self.showCapturePage()
            }
            switch message["event"] as? String {
            case "upload": WKInterfaceDevice.current().play(.click)
            case "success": WKInterfaceDevice.current().play(.success)
            case "failure": WKInterfaceDevice.current().play(.failure)
            default: return
            }
            if let text = message["message"] as? String { self.message = text }
            #endif
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if self.handleWorkoutSync(message) {
                await self.prepareReportSensorIndex()
                let acknowledged = Set((UserDefaults.standard.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
                let history = DataManager.shared.workoutHistory
                var response: [String: Any] = ["workout_history_ready": true, "workout_history_count": history.count,
                              "workout_history_pending": history.filter { !acknowledged.contains($0.id) }.count,
                              "workout_timeline_pending": self.pendingTimelineCount,
                              "workout_timeline_failed": self.timelineReadFailed || self.reportSensorReadFailed || !self.failedReportSensorTransfers.isEmpty,
                              "workout_report_version": 1,
                              WorkoutReportSensors.capabilityKey: 1,
                              "workout_report_sensor_pending": self.pendingReportSensorCount,
                              "workout_report_sensor_failed": self.reportSensorReadFailed || !self.failedReportSensorTransfers.isEmpty]
                if history.contains(where: { !acknowledged.contains($0.id) && !WorkoutSync.supports($0, exercises: self.receiverExercises) }) {
                    response["exercise_update_required"] = true
                }
                if message["kind"] as? String == WorkoutSync.requestKind,
                   message["workout_report_version"] as? Int != 1,
                   history.contains(where: { $0.workoutReport != nil && !acknowledged.contains($0.id) }) {
                    response["workout_report_update_required"] = true
                }
                if message["kind"] as? String == WorkoutSync.requestKind,
                   message[WorkoutReportSensors.capabilityKey] as? Int != 1,
                   self.reportSensorIndex.values.contains(where: { !$0.isEmpty }) {
                    response["report_sensors_update_required"] = true
                }
                if let text = message["timeline_id"] as? String, let id = UUID(uuidString: text) {
                    response["workout_timeline_id"] = text
                    response["workout_timeline_available"] = history.first(where: { $0.id == id })?.workoutReport != nil
                        ? !(self.reportSensorIndex[id] ?? []).isEmpty
                        : FileManager.default.fileExists(atPath: DataManager.shared.timelineArchive.fileURL(id).path)
                }
                replyHandler(response)
                return
            }
            await self.handle(message, reply: replyHandler)
        }
    }

    // Reuse the existing WCSession delegate. Workout messages never replace the
    // application context used by synchronized video capture.
    func syncWorkouts(retry: Bool = false) {
        if retry {
            submittedWorkouts = []; submittedTimelines = []
            reportAttempts = [:]; reportRetries.values.forEach { $0.cancel() }; reportRetries = [:]
            timelineAttempts = [:]
            timelineReadFailed = false; preparedLegacyTimelines = false
            timelineRetries.values.forEach { $0.cancel() }; timelineRetries = [:]
            resetReportSensorRetry()
        }
        let session = WCSession.default
        guard allowsAutomaticAuthorization, session.activationState == .activated, session.isCompanionAppInstalled else { return }
        syncWorkoutTimelines()
        syncReportSensors()
        let defaults = UserDefaults.standard
        let receiver = defaults.string(forKey: "workoutSync.receiver")
        let acknowledged = Set((defaults.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
        let transfers = session.outstandingUserInfoTransfers.filter { $0.userInfo["kind"] as? String == WorkoutSync.batchKind }
        let reportTransfers = session.outstandingFileTransfers.filter { $0.file.metadata?["kind"] as? String == WorkoutSync.reportFileKind }
        if retry && session.isReachable {
            for transfer in transfers { sendWorkoutBatchImmediately(transfer.userInfo) }
        }
        var queued = transfers.reduce(into: Set<UUID>()) { $0.formUnion(WorkoutSync.ids($1.userInfo)) }
        queued.formUnion(reportTransfers.filter { $0.file.metadata?["receiver_id"] as? String == receiver }
            .compactMap { ($0.file.metadata?["id"] as? String).flatMap(UUID.init(uuidString:)) })
        let pending = DataManager.shared.workoutHistory.filter {
            !acknowledged.contains($0.id) && !queued.contains($0.id) && !submittedWorkouts.contains($0.id) &&
                ($0.workoutReport == nil || acceptsWorkoutReports) && WorkoutSync.supports($0, exercises: receiverExercises)
        }
        let slots = max(0, 3 - transfers.count - reportTransfers.count)
        guard slots > 0 else { return }
        var batch: [WorkoutSync.Record] = []
        var submitted = 0
        func sendBatch() {
            guard !batch.isEmpty, submitted < slots, let payload = try? WorkoutSync.message(batch) else { return }
            submittedWorkouts.formUnion(batch.map(\.id))
            session.transferUserInfo(payload)
            if session.isReachable { sendWorkoutBatchImmediately(payload) }
            submitted += 1; batch = []
        }
        for history in pending {
            guard submitted < slots else { break }
            let record = WorkoutSync.Record(id: history.id, date: history.date, exercise: history.exerciseType.rawValue,
                totalReps: history.totalReps, maxWeight: history.maxWeight, duration: history.duration,
                activeDuration: history.activeDuration, totalWeight: history.totalWeight, workoutReport: history.workoutReport)
            if record.workoutReport != nil || (try? WorkoutSync.message([record])) == nil {
                guard acceptsWorkoutReports, let receiver else { continue }
                sendBatch()
                guard submitted < slots else { break }
                do {
                    var payload = try WorkoutSync.message([record], asFile: true)
                    payload["receiver_id"] = receiver
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("WorkoutReportOutbox").appendingPathComponent(receiver)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent(record.id.uuidString + ".plist")
                    try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0).write(to: url, options: .atomic)
                    session.transferFile(url, metadata: ["kind": WorkoutSync.reportFileKind,
                        "id": record.id.uuidString, "receiver_id": receiver])
                    submittedWorkouts.insert(record.id); submitted += 1
                } catch { message = String(localized: "训练报告同步失败，请重试") }
            } else {
                if batch.count == WorkoutSync.maximumBatchSize || (try? WorkoutSync.message(batch + [record])) == nil { sendBatch() }
                guard submitted < slots else { break }
                batch.append(record)
            }
        }
        sendBatch()
    }

    private var receiverExercises: Set<String> {
        let defaults = UserDefaults.standard
        guard let receiver = defaults.string(forKey: "workoutSync.receiver"),
              defaults.string(forKey: "workoutSync.exerciseReceiver") == receiver,
              let exercises = defaults.stringArray(forKey: "workoutSync.supportedExercises") else { return WorkoutSync.legacyExercises }
        return Set(exercises)
    }

    private var acceptsWorkoutReports: Bool {
        let defaults = UserDefaults.standard
        guard let receiver = defaults.string(forKey: "workoutSync.receiver") else { return false }
        return defaults.string(forKey: "workoutReportSync.receiver") == receiver
    }

    private var pendingTimelineCount: Int {
        guard acceptsWorkoutTimelines else { return pendingReportSensorCount }
        if !preparedLegacyTimelines || preparingLegacyTimelines { return 1 + pendingReportSensorCount }
        let acknowledged = Set((UserDefaults.standard.stringArray(forKey: "timelineSync.received") ?? []).compactMap(UUID.init(uuidString:)))
        return DataManager.shared.workoutHistory.filter {
            !acknowledged.contains($0.id) &&
            FileManager.default.fileExists(atPath: DataManager.shared.timelineArchive.fileURL($0.id).path)
        }.count + pendingReportSensorCount
    }

    private var acceptsWorkoutTimelines: Bool {
        let defaults = UserDefaults.standard
        guard let receiver = defaults.string(forKey: "workoutSync.receiver") else { return false }
        return defaults.string(forKey: "timelineSync.receiver") == receiver
    }

    private func syncWorkoutTimelines() {
        let session = WCSession.default
        guard allowsAutomaticAuthorization, session.activationState == .activated,
              session.isCompanionAppInstalled, acceptsWorkoutTimelines else { return }
        if !preparedLegacyTimelines {
            guard !preparingLegacyTimelines else { return }
            preparingLegacyTimelines = true
            Task { @MainActor in
                do { try await DataManager.shared.prepareWorkoutTimelines() }
                catch {
                    timelineReadFailed = true
                    message = String(localized: "部分时间轴读取失败，请重试同步")
                }
                preparedLegacyTimelines = true
                preparingLegacyTimelines = false
                syncWorkoutTimelines()
            }
            return
        }
        let defaults = UserDefaults.standard
        let receiver = defaults.string(forKey: "workoutSync.receiver")
        let acknowledged = Set((defaults.stringArray(forKey: "timelineSync.received") ?? []).compactMap(UUID.init(uuidString:)))
        let transfers = session.outstandingFileTransfers.filter { $0.file.metadata?["kind"] as? String == WorkoutTimeline.fileKind }
        let queued = Set(transfers.compactMap { ($0.file.metadata?["id"] as? String).flatMap(UUID.init(uuidString:)) })
        let slots = max(0, 3 - transfers.count)
        guard slots > 0 else { return }
        var submitted = 0
        for workout in DataManager.shared.workoutHistory where !acknowledged.contains(workout.id) &&
            !queued.contains(workout.id) && !submittedTimelines.contains(workout.id) && (timelineAttempts[workout.id] ?? 0) < 3 {
            guard WorkoutSync.supports(workout, exercises: receiverExercises) else { continue }
            guard submitted < slots else { break }
            do {
                let url = DataManager.shared.timelineArchive.fileURL(workout.id)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                      let size = attributes.fileSize, size <= WorkoutTimeline.maximumFileBytes else { throw WorkoutTimeline.Failure.invalid }
                var metadata: [String: Any] = ["kind": WorkoutTimeline.fileKind, "id": workout.id.uuidString]
                if let receiver { metadata["receiver_id"] = receiver }
                session.transferFile(url, metadata: metadata)
                submittedTimelines.insert(workout.id)
                timelineAttempts[workout.id, default: 0] += 1
                submitted += 1
            } catch {
                timelineReadFailed = true
                message = String(localized: "部分时间轴读取失败，请重试同步")
            }
        }
    }

    private var acceptsReportSensors: Bool {
        guard acceptsWorkoutReports, let receiver = UserDefaults.standard.string(forKey: "workoutSync.receiver") else { return false }
        return UserDefaults.standard.string(forKey: "reportSensorSync.receiver") == receiver
    }
    private func reportSensorKey(_ workoutID: UUID, _ segmentID: UUID) -> String {
        workoutID.uuidString + "/" + segmentID.uuidString
    }
    private var pendingReportSensorCount: Int {
        guard acceptsReportSensors else { return 0 }
        let ids = Set(DataManager.shared.workoutHistory.filter { $0.workoutReport != nil }.map(\.id))
        guard indexedReportIDs == ids else { return ids.isEmpty ? 0 : 1 }
        let acknowledged = Set(UserDefaults.standard.stringArray(forKey: "reportSensorSync.received") ?? [])
        return reportSensorIndex.reduce(0) { count, entry in
            count + entry.value.filter { !acknowledged.contains(reportSensorKey(entry.key, $0)) }.count
        }
    }
    private func invalidateReportSensorIndex() {
        reportSensorScanGeneration = UUID()
        reportSensorScanTask?.cancel(); reportSensorScanTask = nil
        indexedReportIDs = nil; reportSensorIndex = [:]; reportSensorReadFailed = false
    }
    private func resetReportSensorRetry() {
        submittedReportSensors = []; reportSensorAttempts = [:]
        failedReportSensorTransfers = []
        reportSensorRetries.values.forEach { $0.cancel() }; reportSensorRetries = [:]
        invalidateReportSensorIndex()
    }
    private func prepareReportSensorIndex() async {
        let sources = DataManager.shared.workoutHistory.filter { $0.workoutReport != nil }.map {
            WorkoutSync.Record(id: $0.id, date: $0.date, exercise: $0.exerciseType.rawValue,
                totalReps: $0.totalReps, maxWeight: $0.maxWeight, duration: $0.duration,
                activeDuration: $0.activeDuration, totalWeight: $0.totalWeight, workoutReport: $0.workoutReport)
        }
        let ids = Set(sources.map(\.id))
        if indexedReportIDs == ids { return }
        if let task = reportSensorScanTask { await task.value; return }
        let archive = DataManager.shared.reportSensorArchive, generation = reportSensorScanGeneration
        let task = Task { @MainActor [weak self] in
            do {
                let result = try await WorkoutFileIO.shared.perform { () -> ([UUID: [UUID]], Bool) in
                    var index: [UUID: [UUID]] = [:], failed = false
                    for source in sources {
                        do { index[source.id] = try archive.index(for: source).map(\.id) }
                        catch { failed = true }
                    }
                    return (index, failed)
                }
                guard !Task.isCancelled, let self, self.reportSensorScanGeneration == generation else { return }
                self.reportSensorIndex = result.0; self.reportSensorReadFailed = result.1
                self.indexedReportIDs = ids; self.reportSensorScanTask = nil
                if result.1 { self.message = String(localized: "部分时间轴读取失败，请重试同步") }
            } catch {
                guard !Task.isCancelled, let self, self.reportSensorScanGeneration == generation else { return }
                self.reportSensorReadFailed = true; self.reportSensorScanTask = nil
                self.message = String(localized: "部分时间轴读取失败，请重试同步")
            }
        }
        reportSensorScanTask = task
        await task.value
    }
    private func syncReportSensors() {
        let session = WCSession.default
        guard allowsAutomaticAuthorization, session.activationState == .activated,
              session.isCompanionAppInstalled, acceptsReportSensors,
              let receiver = UserDefaults.standard.string(forKey: "workoutSync.receiver") else { return }
        if reportSensorSyncing { reportSensorSyncRequested = true; return }
        reportSensorSyncing = true
        Task { @MainActor in
            defer {
                reportSensorSyncing = false
                if reportSensorSyncRequested { reportSensorSyncRequested = false; syncReportSensors() }
            }
            await prepareReportSensorIndex()
            guard acceptsReportSensors, receiver == UserDefaults.standard.string(forKey: "workoutSync.receiver") else { return }
            let known = Set(DataManager.shared.workoutHistory.filter {
                $0.workoutReport != nil && WorkoutSync.supports($0, exercises: receiverExercises)
            }.map(\.id))
            let parents = Set((UserDefaults.standard.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
            let received = Set(UserDefaults.standard.stringArray(forKey: "reportSensorSync.received") ?? [])
            let transfers = session.outstandingFileTransfers.filter { $0.file.metadata?["kind"] as? String == WorkoutReportSensors.fileKind }
            var queued = Set<String>()
            for transfer in transfers {
                let metadata = transfer.file.metadata ?? [:]
                guard metadata["receiver_id"] as? String == receiver,
                      let text = metadata["workout_id"] as? String, let parent = UUID(uuidString: text), known.contains(parent),
                      let childText = metadata["id"] as? String, let child = UUID(uuidString: childText) else { transfer.cancel(); continue }
                queued.insert(reportSensorKey(parent, child))
            }
            var slots = max(0, 3 - queued.count)
            for parent in reportSensorIndex.keys.sorted(by: { $0.uuidString < $1.uuidString }) where known.contains(parent) && parents.contains(parent) {
                for segment in reportSensorIndex[parent] ?? [] {
                    guard slots > 0 else { return }
                    let key = reportSensorKey(parent, segment)
                    guard !received.contains(key), !queued.contains(key), !submittedReportSensors.contains(key),
                          (reportSensorAttempts[key] ?? 0) < 3 else { continue }
                    let url = DataManager.shared.reportSensorArchive.fileURL(workoutID: parent, segmentID: segment)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    session.transferFile(url, metadata: ["kind": WorkoutReportSensors.fileKind,
                        "id": segment.uuidString, "workout_id": parent.uuidString, "receiver_id": receiver])
                    submittedReportSensors.insert(key); reportSensorAttempts[key, default: 0] += 1; slots -= 1
                }
            }
        }
    }
    private func scheduleReportSensorRetry(workoutID: UUID, segmentID: UUID, receiver: String) {
        let key = reportSensorKey(workoutID, segmentID)
        reportSensorRetries[key]?.cancel()
        reportSensorRetries[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.acceptsReportSensors,
                  UserDefaults.standard.string(forKey: "workoutSync.receiver") == receiver,
                  DataManager.shared.workoutHistory.contains(where: { $0.id == workoutID }),
                  !(UserDefaults.standard.stringArray(forKey: "reportSensorSync.received") ?? []).contains(key) else { return }
            self.reportSensorRetries.removeValue(forKey: key)
            guard (self.reportSensorAttempts[key] ?? 0) < 3 else {
                self.failedReportSensorTransfers.insert(key)
                self.message = String(localized: "时间轴尚未同步，请重试"); return
            }
            self.submittedReportSensors.remove(key); self.syncReportSensors()
        }
    }
    func cancelReportSensors(workoutIDs: Set<UUID>) {
        failedReportSensorTransfers = failedReportSensorTransfers.filter { key in
            !workoutIDs.contains(where: { key.hasPrefix($0.uuidString + "/") })
        }
        for transfer in WCSession.default.outstandingFileTransfers where transfer.file.metadata?["kind"] as? String == WorkoutReportSensors.fileKind {
            if let text = transfer.file.metadata?["workout_id"] as? String, let id = UUID(uuidString: text), workoutIDs.contains(id) { transfer.cancel() }
        }
        for key in Array(reportSensorRetries.keys) where workoutIDs.contains(where: { key.hasPrefix($0.uuidString + "/") }) {
            reportSensorRetries.removeValue(forKey: key)?.cancel(); reportSensorAttempts.removeValue(forKey: key)
            submittedReportSensors.remove(key)
        }
        let received = UserDefaults.standard.stringArray(forKey: "reportSensorSync.received") ?? []
        UserDefaults.standard.set(received.filter { key in !workoutIDs.contains(where: { key.hasPrefix($0.uuidString + "/") }) }, forKey: "reportSensorSync.received")
        invalidateReportSensorIndex()
    }

    private var reportRetries: [UUID: Task<Void, Never>] = [:]
    private var reportAttempts: [UUID: Int] = [:]
    private func scheduleWorkoutReceiptRetry(_ ids: Set<UUID>) {
        guard acceptsWorkoutReports,
              let receiver = UserDefaults.standard.string(forKey: "workoutSync.receiver") else { return }
        for id in ids {
            reportRetries[id]?.cancel()
            guard (reportAttempts[id] ?? 0) < 3 else { continue }
            reportAttempts[id, default: 0] += 1
            reportRetries[id] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.acceptsWorkoutReports,
                      UserDefaults.standard.string(forKey: "workoutSync.receiver") == receiver else { return }
                self.reportRetries.removeValue(forKey: id)
                let received = UserDefaults.standard.stringArray(forKey: "workoutSync.received") ?? []
                guard !received.contains(id.uuidString) else { return }
                self.submittedWorkouts.remove(id)
                self.syncWorkouts()
            }
        }
    }

    private func sendWorkoutBatchImmediately(_ payload: [String: Any]) {
        WCSession.default.sendMessage(payload, replyHandler: { reply in
            Task { @MainActor in _ = self.handleWorkoutSync(reply) }
        }, errorHandler: { _ in /* Background transfer remains queued. */ })
    }

    func receiveBackgroundUpdates() async {
        let session = WCSession.default
        if session.activationState != .activated { session.activate() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        repeat {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        } while !Task.isCancelled && ContinuousClock.now < deadline &&
            (session.activationState != .activated || session.hasContentPending)
        if !Task.isCancelled { syncWorkouts() }
    }

    @discardableResult
    private func handleWorkoutSync(_ payload: [String: Any]) -> Bool {
        guard let kind = payload["kind"] as? String,
              kind == WorkoutSync.requestKind || kind == WorkoutSync.receiptKind ||
              kind == WorkoutTimeline.receiptKind || kind == WorkoutReportSensors.receiptKind else { return false }
        guard let receiver = payload["receiver_id"] as? String, UUID(uuidString: receiver) != nil else { return true }
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "workoutSync.receiver")
        if kind == WorkoutReportSensors.receiptKind {
            guard previous == receiver, acceptsReportSensors,
                  let parentText = payload["workout_id"] as? String, let parent = UUID(uuidString: parentText),
                  DataManager.shared.workoutHistory.contains(where: { $0.id == parent && $0.workoutReport != nil }) else { return true }
            let received = WorkoutSync.ids(payload).filter {
                FileManager.default.fileExists(atPath: DataManager.shared.reportSensorArchive.fileURL(workoutID: parent, segmentID: $0).path)
            }
            var acknowledged = Set(defaults.stringArray(forKey: "reportSensorSync.received") ?? [])
            for segment in received {
                let key = reportSensorKey(parent, segment)
                acknowledged.insert(key); submittedReportSensors.remove(key)
                failedReportSensorTransfers.remove(key)
                reportSensorRetries.removeValue(forKey: key)?.cancel(); reportSensorAttempts.removeValue(forKey: key)
            }
            defaults.set(Array(acknowledged), forKey: "reportSensorSync.received")
            for transfer in WCSession.default.outstandingFileTransfers where transfer.file.metadata?["kind"] as? String == WorkoutReportSensors.fileKind && transfer.file.metadata?["workout_id"] as? String == parent.uuidString {
                if let text = transfer.file.metadata?["id"] as? String, let id = UUID(uuidString: text), received.contains(id) { transfer.cancel() }
            }
            syncReportSensors()
            return true
        }
        if kind == WorkoutTimeline.receiptKind {
            guard previous == nil || previous == receiver else { return true }
            defaults.set(receiver, forKey: "workoutSync.receiver")
            let known = Set(DataManager.shared.workoutHistory.map(\.id))
            let received = WorkoutSync.ids(payload).intersection(known)
            var acknowledged = Set((defaults.stringArray(forKey: "timelineSync.received") ?? []).compactMap(UUID.init(uuidString:)))
            acknowledged.formUnion(received)
            defaults.set(acknowledged.map(\.uuidString), forKey: "timelineSync.received")
            submittedTimelines.subtract(received)
            for id in received {
                timelineRetries.removeValue(forKey: id)?.cancel()
                timelineAttempts.removeValue(forKey: id)
            }
            for transfer in WCSession.default.outstandingFileTransfers where transfer.file.metadata?["kind"] as? String == WorkoutTimeline.fileKind {
                if let text = transfer.file.metadata?["id"] as? String, let id = UUID(uuidString: text), received.contains(id) { transfer.cancel() }
            }
            syncWorkoutTimelines()
            return true
        }
        if kind == WorkoutSync.requestKind {
            let exercises = WorkoutSync.supportedExercises(in: payload)
            defaults.set(receiver, forKey: "workoutSync.exerciseReceiver")
            defaults.set(Array(exercises), forKey: "workoutSync.supportedExercises")
            submittedWorkouts = []; submittedTimelines = []
            // Never let a new movement in a queued batch poison otherwise
            // compatible old workouts after switching or downgrading the phone.
            for transfer in WCSession.default.outstandingUserInfoTransfers where transfer.userInfo["kind"] as? String == WorkoutSync.batchKind {
                if let records = try? WorkoutSync.decode(transfer.userInfo), records.contains(where: { !exercises.contains($0.exercise) }) {
                    transfer.cancel()
                }
            }
            let unsupported = Set(DataManager.shared.workoutHistory.filter { !WorkoutSync.supports($0, exercises: exercises) }.map(\.id))
            for transfer in WCSession.default.outstandingFileTransfers {
                let metadata = transfer.file.metadata ?? [:]
                let kind = metadata["kind"] as? String
                guard [WorkoutSync.reportFileKind, WorkoutTimeline.fileKind, WorkoutReportSensors.fileKind].contains(kind ?? "") else { continue }
                let id = (metadata[kind == WorkoutReportSensors.fileKind ? "workout_id" : "id"] as? String).flatMap(UUID.init(uuidString:))
                if let id, unsupported.contains(id) { transfer.cancel() }
            }
            timelineAttempts = [:]
            timelineReadFailed = false; preparedLegacyTimelines = false
            timelineRetries.values.forEach { $0.cancel() }; timelineRetries = [:]
            if payload["timeline_version"] as? Int == 1 { defaults.set(receiver, forKey: "timelineSync.receiver") }
            else if previous != receiver { defaults.removeObject(forKey: "timelineSync.receiver") }
            if payload["workout_report_version"] as? Int == 1 {
                defaults.set(receiver, forKey: "workoutReportSync.receiver")
                if message == String(localized: "请更新 iPhone App 以同步训练报告") { message = "" }
            } else {
                defaults.removeObject(forKey: "workoutReportSync.receiver")
                let received = Set((defaults.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
                if DataManager.shared.workoutHistory.contains(where: {
                    $0.workoutReport != nil && (previous != receiver || !received.contains($0.id))
                }) { message = String(localized: "请更新 iPhone App 以同步训练报告") }
            }
            if payload[WorkoutReportSensors.capabilityKey] as? Int == 1, payload["workout_report_version"] as? Int == 1 {
                defaults.set(receiver, forKey: "reportSensorSync.receiver")
            } else { defaults.removeObject(forKey: "reportSensorSync.receiver") }
            let received = Set((defaults.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
            if !unsupported.subtracting(previous == receiver ? received : []).isEmpty {
                message = String(localized: "请更新 iPhone App 以同步新增动作")
            } else if message == String(localized: "请更新 iPhone App 以同步新增动作") { message = "" }
            for transfer in WCSession.default.outstandingFileTransfers where transfer.file.metadata?["kind"] as? String == WorkoutReportSensors.fileKind {
                if transfer.file.metadata?["receiver_id"] as? String != receiver || payload[WorkoutReportSensors.capabilityKey] as? Int != 1 || payload["workout_report_version"] as? Int != 1 { transfer.cancel() }
            }
            for transfer in WCSession.default.outstandingFileTransfers where transfer.file.metadata?["kind"] as? String == WorkoutSync.reportFileKind {
                if transfer.file.metadata?["receiver_id"] as? String != receiver || payload["workout_report_version"] as? Int != 1 {
                    transfer.cancel()
                }
            }
            if previous != receiver || payload["force"] as? Bool == true {
                if previous == receiver, let text = payload["timeline_id"] as? String, let id = UUID(uuidString: text) {
                    // A missing phone file can be retried without replaying every workout.
                    let received = defaults.stringArray(forKey: "timelineSync.received") ?? []
                    defaults.set(received.filter { UUID(uuidString: $0) != id }, forKey: "timelineSync.received")
                    let segments = defaults.stringArray(forKey: "reportSensorSync.received") ?? []
                    defaults.set(segments.filter { !$0.hasPrefix(id.uuidString + "/") }, forKey: "reportSensorSync.received")
                } else {
                    defaults.set([String](), forKey: "workoutSync.received")
                    defaults.set([String](), forKey: "timelineSync.received")
                    defaults.set([String](), forKey: "reportSensorSync.received")
                }
                preparedLegacyTimelines = false
                for transfer in WCSession.default.outstandingFileTransfers where transfer.file.metadata?["kind"] as? String == WorkoutTimeline.fileKind {
                    if transfer.file.metadata?["receiver_id"] as? String != receiver { transfer.cancel() }
                }
            }
            defaults.set(receiver, forKey: "workoutSync.receiver")
        } else {
            guard previous == nil || previous == receiver else { return true }
            defaults.set(receiver, forKey: "workoutSync.receiver")
            let known = Set(DataManager.shared.workoutHistory.filter {
                $0.workoutReport == nil || (acceptsWorkoutReports && payload["workout_report_version"] as? Int == 1)
            }.map(\.id))
            var acknowledged = Set((defaults.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
            acknowledged.formUnion(WorkoutSync.ids(payload).intersection(known))
            defaults.set(acknowledged.map(\.uuidString), forKey: "workoutSync.received")
            for id in WorkoutSync.ids(payload).intersection(known) {
                reportRetries[id]?.cancel(); reportRetries.removeValue(forKey: id); reportAttempts.removeValue(forKey: id)
                let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("WorkoutReportOutbox").appendingPathComponent(receiver).appendingPathComponent(id.uuidString + ".plist")
                let inFlight = WCSession.default.outstandingFileTransfers.contains { $0.file.fileURL == url }
                if !inFlight { try? FileManager.default.removeItem(at: url) }
            }
            for transfer in WCSession.default.outstandingUserInfoTransfers where transfer.userInfo["kind"] as? String == WorkoutSync.batchKind {
                if WorkoutSync.ids(transfer.userInfo).isSubset(of: acknowledged) { transfer.cancel() }
            }
        }
        syncWorkouts(retry: kind == WorkoutSync.requestKind)
        return true
    }

    func showCapturePage(exercise: String? = nil) {
        let store = CollectionStore.shared
        if let draft = store.draft { requestedExercise = draft.exercise }
        else if !store.recording, let exercise,
                (ExerciseType(rawValue: exercise) != nil || ["rest", "walking", "other"].contains(exercise)) {
            requestedExercise = exercise
        }
        showingCapture = true
    }

    func handle(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) async {
        #if DEBUG
        let received = Date().timeIntervalSince1970
        guard let command = message["command"] as? String else { reply(["error": String(localized: "无效指令")]); return }
        let store = CollectionStore.shared
        if command == "ping" {
            reply(["received": received, "sent": Date().timeIntervalSince1970]); return
        }
        if command == "prepare" {
            guard !store.recording, store.draft == nil else { reply(["error": String(localized: "请先保存手表上的当前采集")]); return }
            guard DataManager.shared.currentSession == nil else { reply(["error": String(localized: "请先结束手表上的当前训练")]); return }
            showCapturePage(exercise: message["exercise"] as? String)
            if authorizing {
                reply(["authorizationPending": true]); return
            }
            refreshAuthorization()
            if attemptedInitialAuthorization && needsAuthorization {
                reply(["error": String(localized: "手表尚未授权，请在手表检查同步权限")]); return
            }
            if !["bench_press", "squat"].contains(message["exercise"] as? String ?? "") { WKInterfaceDevice.current().play(.click) }
            // A transport reply must never wait for a human to dismiss a permission sheet.
            guard !needsAuthorization else {
                reply(["authorizationPending": true])
                // The foreground capture view presents authorization after it is visible.
                return
            }
            self.message = String(localized: "正在准备采集…")
            reply(["ready": true])
            return
        }
        guard let text = message["id"] as? String, let id = UUID(uuidString: text) else { reply(["error": String(localized: "采集编号无效")]); return }
        if command == "start" {
            if activeID == id, store.recording { reply(["started": true]); return }
            guard activeID == nil, !startingCapture, workout == nil, !store.recording, store.draft == nil,
                  let exercise = message["exercise"] as? String,
                  (ExerciseType(rawValue: exercise) != nil || ["rest", "walking", "other"].contains(exercise)) else {
                reply(["error": String(localized: "手表未就绪或动作无效")]); return
            }
            showCapturePage(exercise: exercise)
            do {
                try await startProtectedCapture(exercise: exercise, notes: "iPhone 同步录像 \(id.uuidString)", id: id, remote: true)
                self.message = ""
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.publishStatus() }
                }
                reply(["started": true, "watch_started_at": Date().timeIntervalSince1970])
            } catch {
                workout?.end(); workout = nil; activeID = nil; remoteSession = false
                WKInterfaceDevice.current().play(.failure)
                self.message = error.localizedDescription
                reply(["error": self.message])
            }
        } else if command == "stop" {
            guard activeID == id else {
                let url = completedFiles[id] ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoCaptures/\(id.uuidString).json")
                if FileManager.default.fileExists(atPath: url.path) {
                    let timingURL = url.deletingPathExtension().appendingPathExtension("timing.json")
                    let origin = (try? Data(contentsOf: timingURL)).flatMap { try? JSONDecoder().decode(Double.self, from: $0) } ?? 0
                    WCSession.default.transferFile(url, metadata: ["id": text, "sample_origin": origin]); reply(["stopped": true]); return
                }
                reply(["error": String(localized: "未找到本组采集")]); return
            }
            sampleOrigin = store.sampleOriginWallTime ?? sampleOrigin
            store.finish()
            reply(["stopped": true])
        } else { reply(["error": String(localized: "未知指令")]) }
        #else
        reply(["error": String(localized: "无效指令")])
        #endif
    }

    func startStandaloneCapture(exercise: String, notes: String) async {
        do {
            try await startProtectedCapture(exercise: exercise, notes: notes, id: UUID(), remote: false)
        } catch {
            guard !(error is CancellationError) else { return }
            message = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func cancelStandaloneStart() {
        guard pendingStandaloneStart != nil else { return }
        pendingStandaloneStart = nil
        let session = workout
        workout = nil
        session?.end()
    }

    private func startProtectedCapture(exercise: String, notes: String, id: UUID, remote: Bool) async throws {
        let store = CollectionStore.shared
        func failure(_ text: String) -> NSError {
            NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
        }
        guard !startingCapture, workout == nil, !store.recording, store.draft == nil,
              DataManager.shared.currentSession == nil else { throw failure(String(localized: "请先结束或保存当前采集")) }
        startingCapture = true
        let startToken = UUID()
        if !remote { pendingStandaloneStart = startToken }
        defer {
            startingCapture = false
            if pendingStandaloneStart == startToken { pendingStandaloneStart = nil }
        }
        guard await authorizeCapture() else { throw failure(String(localized: "请先允许体能训练权限")) }
        if !remote && pendingStandaloneStart != startToken { throw CancellationError() }
        guard !store.recording, store.draft == nil, DataManager.shared.currentSession == nil else {
            throw failure(String(localized: "请先结束或保存当前采集"))
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: health, configuration: config)
        session.delegate = self
        workout = session
        do {
            session.startActivity(with: Date())
            // Background protection is active only once the session is running.
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while session.state != .running {
                if !remote && pendingStandaloneStart != startToken { throw CancellationError() }
                guard workout === session, ContinuousClock.now < deadline else {
                    throw failure(String(localized: "训练会话启动失败，请重试"))
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            if !remote && pendingStandaloneStart != startToken { throw CancellationError() }
            activeID = remote ? id : nil
            remoteSession = remote
            sampleOrigin = nil
            captureLog.info("Capture workout running; remote=\(remote)")
            store.begin(exercise, pace: "normal", notes: notes, sessionID: id)
            guard store.recording else { throw failure(String(localized: "加速度计不可用")) }
        } catch {
            workout = nil
            session.end()
            activeID = nil
            remoteSession = false
            throw error
        }
    }

    private func publishStatus() {
        guard let id = activeID else { return }
        sampleOrigin = CollectionStore.shared.sampleOriginWallTime ?? sampleOrigin
        let status: [String: Any] = ["id": id.uuidString, "count": CollectionStore.shared.detected,
                                   "recording": CollectionStore.shared.recording,
                                   "sample_origin": sampleOrigin ?? 0]
        guard lastPublishedStatus != status as NSDictionary else { return }
        lastPublishedStatus = status as NSDictionary
        try? WCSession.default.updateApplicationContext(status)
        if WCSession.default.isReachable { WCSession.default.sendMessage(status, replyHandler: nil, errorHandler: nil) }
    }

    func noteSampleOrigin(_ origin: Double?) { sampleOrigin = origin ?? sampleOrigin }

    // Entering capture requests permission once; returning from the system sheet must not reopen it.
    func requestInitialCaptureAuthorization() async {
        guard allowsAutomaticAuthorization, !attemptedInitialAuthorization, !authorizing,
              !CollectionStore.shared.recording, CollectionStore.shared.draft == nil else { return }
        attemptedInitialAuthorization = true
        _ = await authorizeCapture()
    }

    func refreshAuthorization() {
        needsAuthorization = !authorization.available() || authorization.status() != .sharingAuthorized
        if !needsAuthorization {
            authorizationMessage = ""
            showingAuthorizationHelp = false
        }
    }

    func authorizeCapture() async -> Bool {
        guard authorization.available() else {
            authorizationMessage = String(localized: "健康功能暂不可用"); showingAuthorizationHelp = true; return false
        }
        refreshAuthorization()
        if !needsAuthorization { return true }
        guard !authorizing else { return false }
        authorizing = true; authorizationMessage = ""
        defer { authorizing = false; refreshAuthorization() }
        do {
            let requestStatus = try await authorization.requestStatus()
            authorizationLog.info("Checking workout write permission: status=\(self.authorization.status().rawValue), request=\(requestStatus.rawValue)")
            // Already-decided permissions do not present a sheet. Never promise another popup.
            if requestStatus != .unnecessary { try await authorization.request() }
            refreshAuthorization()
            guard !needsAuthorization else {
                authorizationMessage = String(localized: "手表尚未获得体能训练权限")
                showingAuthorizationHelp = true
                WKInterfaceDevice.current().play(.failure)
                return false
            }
            return true
        } catch {
            let failure = error as NSError
            authorizationLog.error("Authorization failed: \(failure.domain, privacy: .public) / \(failure.code)")
            authorizationMessage = String(localized: "权限检查失败（\(failure.code)），请重试")
            showingAuthorizationHelp = true
            WKInterfaceDevice.current().play(.failure)
            return false
        }
    }

    func startFromWatch(exercise: String) async {
        if !["bench_press", "squat"].contains(exercise) { WKInterfaceDevice.current().play(.click) }
        guard await authorizeCapture() else { return }
        guard !requestingPhone, WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            message = String(localized: "请先打开手机同步采集页"); WKInterfaceDevice.current().play(.failure); return
        }
        requestingPhone = true; message = String(localized: "正在连接手机相机…")
        let requestID = UUID()
        phoneRequestID = requestID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard self.phoneRequestID == requestID, self.requestingPhone else { return }
            self.phoneRequestID = nil; self.requestingPhone = false
            self.message = String(localized: "手机响应超时，请打开同步采集页后重试")
            WKInterfaceDevice.current().play(.failure)
        }
        WCSession.default.sendMessage(["command": "startFromWatch", "exercise": exercise], replyHandler: { response in
            Task { @MainActor in
                guard self.phoneRequestID == requestID else { return }
                self.phoneRequestID = nil
                self.requestingPhone = false
                self.message = response["error"] as? String ?? String(localized: "正在准备采集…")
                if response["error"] != nil { WKInterfaceDevice.current().play(.failure) }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard self.phoneRequestID == requestID else { return }
                self.phoneRequestID = nil; self.requestingPhone = false
                self.message = String(localized: "手机未响应，请打开同步采集页")
                WKInterfaceDevice.current().play(.failure)
            }
        })
    }

    func captureFinished() {
        timer?.invalidate(); timer = nil
        let finishedWorkout = workout
        workout = nil
        finishedWorkout?.end()
        captureLog.info("Capture workout ended")
        guard let id = activeID else { return }
        defer { activeID = nil; remoteSession = false }
        let store = CollectionStore.shared
        guard let record = store.draft else {
            try? WCSession.default.updateApplicationContext(["id": id.uuidString, "recording": false, "error": store.message]); return
        }
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoCaptures")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let url = folder.appendingPathComponent(id.uuidString + ".json")
            try encoder.encode(record).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try JSONEncoder().encode(sampleOrigin ?? 0).write(to: url.deletingPathExtension().appendingPathExtension("timing.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            completedFiles[id] = url
            WCSession.default.transferFile(url, metadata: ["id": id.uuidString, "sample_origin": sampleOrigin ?? 0])
            try WCSession.default.updateApplicationContext(["id": id.uuidString, "recording": false, "count": store.detected, "sample_origin": sampleOrigin ?? 0])
            store.discard()
            message = String(localized: "请在手机核对并上传")
            showingPhoneReview = true
        } catch { store.message = String(localized: "同步文件保存失败，数据仍在本页") }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.captureLog.info("Workout state changed: \(fromState.rawValue) -> \(toState.rawValue)")
            if self.workout === workoutSession, toState == .ended || toState == .paused {
                if CollectionStore.shared.recording {
                    CollectionStore.shared.finish(interruption: String(localized: "训练会话中断"))
                } else { self.workout = nil }
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            let failure = error as NSError
            self.captureLog.error("Workout failed: \(failure.domain, privacy: .public) / \(failure.code)")
            guard self.workout === workoutSession else { return }
            if CollectionStore.shared.recording {
                CollectionStore.shared.finish(interruption: String(localized: "训练会话中断"))
            } else { self.workout = nil }
        }
    }
}
#endif
