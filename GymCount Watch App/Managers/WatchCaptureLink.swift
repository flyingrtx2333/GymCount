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
    private var sampleOrigin: Double?
    private var completedFiles: [UUID: URL] = [:]
    private var phoneRequestID: UUID?
    private var attemptedInitialAuthorization = false
    private var submittedWorkouts: Set<UUID> = []

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
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if self.handleWorkoutSync(message) {
                let acknowledged = Set((UserDefaults.standard.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
                let history = DataManager.shared.workoutHistory
                replyHandler(["workout_history_ready": true, "workout_history_count": history.count,
                              "workout_history_pending": history.filter { !acknowledged.contains($0.id) }.count])
                return
            }
            await self.handle(message, reply: replyHandler)
        }
    }

    // Reuse the existing WCSession delegate. Workout messages never replace the
    // application context used by synchronized video capture.
    func syncWorkouts(retry: Bool = false) {
        if retry { submittedWorkouts = [] }
        let session = WCSession.default
        guard allowsAutomaticAuthorization, session.activationState == .activated, session.isCompanionAppInstalled else { return }
        let defaults = UserDefaults.standard
        let acknowledged = Set((defaults.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
        let transfers = session.outstandingUserInfoTransfers.filter { $0.userInfo["kind"] as? String == WorkoutSync.batchKind }
        if retry && session.isReachable {
            for transfer in transfers { sendWorkoutBatchImmediately(transfer.userInfo) }
        }
        let queued = transfers.reduce(into: Set<UUID>()) { $0.formUnion(WorkoutSync.ids($1.userInfo)) }
        let pending = DataManager.shared.workoutHistory.filter {
            !acknowledged.contains($0.id) && !queued.contains($0.id) && !submittedWorkouts.contains($0.id)
        }
        let slots = max(0, 3 - transfers.count)
        guard slots > 0 else { return }
        for offset in stride(from: 0, to: min(pending.count, slots * WorkoutSync.maximumBatchSize), by: WorkoutSync.maximumBatchSize) {
            let records = pending[offset..<min(offset + WorkoutSync.maximumBatchSize, pending.count)].map {
                WorkoutSync.Record(id: $0.id, date: $0.date, exercise: $0.exerciseType.rawValue,
                    totalReps: $0.totalReps, maxWeight: $0.maxWeight, duration: $0.duration)
            }
            guard let payload = try? WorkoutSync.message(records) else { continue }
            submittedWorkouts.formUnion(records.map(\.id))
            session.transferUserInfo(payload)
            if session.isReachable { sendWorkoutBatchImmediately(payload) }
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
              kind == WorkoutSync.requestKind || kind == WorkoutSync.receiptKind else { return false }
        guard let receiver = payload["receiver_id"] as? String, UUID(uuidString: receiver) != nil else { return true }
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "workoutSync.receiver")
        if kind == WorkoutSync.requestKind {
            submittedWorkouts = []
            if previous != receiver || payload["force"] as? Bool == true {
                defaults.set([String](), forKey: "workoutSync.received")
            }
            defaults.set(receiver, forKey: "workoutSync.receiver")
        } else {
            guard previous == nil || previous == receiver else { return true }
            defaults.set(receiver, forKey: "workoutSync.receiver")
            let known = Set(DataManager.shared.workoutHistory.map(\.id))
            var acknowledged = Set((defaults.stringArray(forKey: "workoutSync.received") ?? []).compactMap(UUID.init(uuidString:)))
            acknowledged.formUnion(WorkoutSync.ids(payload).intersection(known))
            defaults.set(acknowledged.map(\.uuidString), forKey: "workoutSync.received")
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
                ["squat", "bench_press", "deadlift", "bicep_curl", "rest", "walking", "other"].contains(exercise) {
            requestedExercise = exercise
        }
        showingCapture = true
    }

    func handle(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) async {
        let received = Date().timeIntervalSince1970
        guard let command = message["command"] as? String else { reply(["error": "无效指令"]); return }
        let store = CollectionStore.shared
        if command == "ping" {
            reply(["received": received, "sent": Date().timeIntervalSince1970]); return
        }
        if command == "prepare" {
            guard !store.recording, store.draft == nil else { reply(["error": "请先保存手表上的当前采集"]); return }
            guard DataManager.shared.currentSession == nil else { reply(["error": "请先结束手表上的当前训练"]); return }
            showCapturePage(exercise: message["exercise"] as? String)
            if authorizing {
                reply(["authorizationPending": true]); return
            }
            refreshAuthorization()
            if attemptedInitialAuthorization && needsAuthorization {
                reply(["error": "手表尚未授权，请在手表检查同步权限"]); return
            }
            WKInterfaceDevice.current().play(.click)
            // A transport reply must never wait for a human to dismiss a permission sheet.
            guard !needsAuthorization else {
                reply(["authorizationPending": true])
                // The foreground capture view presents authorization after it is visible.
                return
            }
            self.message = "正在准备采集…"
            reply(["ready": true])
            return
        }
        guard let text = message["id"] as? String, let id = UUID(uuidString: text) else { reply(["error": "采集编号无效"]); return }
        if command == "start" {
            if activeID == id, store.recording { reply(["started": true]); return }
            guard activeID == nil, !startingCapture, workout == nil, !store.recording, store.draft == nil,
                  let exercise = message["exercise"] as? String,
                  ["squat", "bench_press", "deadlift", "bicep_curl", "rest", "walking", "other"].contains(exercise) else {
                reply(["error": "手表未就绪或动作无效"]); return
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
                reply(["error": "未找到本组采集"]); return
            }
            sampleOrigin = store.sampleOriginWallTime ?? sampleOrigin
            store.finish()
            reply(["stopped": true])
        } else { reply(["error": "未知指令"]) }
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
              DataManager.shared.currentSession == nil else { throw failure("请先结束或保存当前采集") }
        startingCapture = true
        let startToken = UUID()
        if !remote { pendingStandaloneStart = startToken }
        defer {
            startingCapture = false
            if pendingStandaloneStart == startToken { pendingStandaloneStart = nil }
        }
        guard await authorizeCapture() else { throw failure("请先允许体能训练权限") }
        if !remote && pendingStandaloneStart != startToken { throw CancellationError() }
        guard !store.recording, store.draft == nil, DataManager.shared.currentSession == nil else {
            throw failure("请先结束或保存当前采集")
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
                    throw failure("训练会话启动失败，请重试")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            if !remote && pendingStandaloneStart != startToken { throw CancellationError() }
            activeID = remote ? id : nil
            remoteSession = remote
            sampleOrigin = nil
            captureLog.info("Capture workout running; remote=\(remote)")
            store.begin(exercise, pace: "normal", notes: notes, sessionID: id)
            guard store.recording else { throw failure("加速度计不可用") }
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
            authorizationMessage = "健康功能暂不可用"; showingAuthorizationHelp = true; return false
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
                authorizationMessage = "手表尚未获得体能训练权限"
                showingAuthorizationHelp = true
                WKInterfaceDevice.current().play(.failure)
                return false
            }
            return true
        } catch {
            let failure = error as NSError
            authorizationLog.error("Authorization failed: \(failure.domain, privacy: .public) / \(failure.code)")
            authorizationMessage = "权限检查失败（\(failure.code)），请重试"
            showingAuthorizationHelp = true
            WKInterfaceDevice.current().play(.failure)
            return false
        }
    }

    func startFromWatch(exercise: String) async {
        WKInterfaceDevice.current().play(.click)
        guard await authorizeCapture() else { return }
        guard !requestingPhone, WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            message = "请先打开手机同步采集页"; WKInterfaceDevice.current().play(.failure); return
        }
        requestingPhone = true; message = "正在连接手机相机…"
        let requestID = UUID()
        phoneRequestID = requestID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard self.phoneRequestID == requestID, self.requestingPhone else { return }
            self.phoneRequestID = nil; self.requestingPhone = false
            self.message = "手机响应超时，请打开同步采集页后重试"
            WKInterfaceDevice.current().play(.failure)
        }
        WCSession.default.sendMessage(["command": "startFromWatch", "exercise": exercise], replyHandler: { response in
            Task { @MainActor in
                guard self.phoneRequestID == requestID else { return }
                self.phoneRequestID = nil
                self.requestingPhone = false
                self.message = response["error"] as? String ?? "正在准备采集…"
                if response["error"] != nil { WKInterfaceDevice.current().play(.failure) }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard self.phoneRequestID == requestID else { return }
                self.phoneRequestID = nil; self.requestingPhone = false
                self.message = "手机未响应，请打开同步采集页"
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
            message = "请在手机核对并上传"
        } catch { store.message = "同步文件保存失败，数据仍在本页" }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.captureLog.info("Workout state changed: \(fromState.rawValue) -> \(toState.rawValue)")
            if self.workout === workoutSession, toState == .ended || toState == .paused {
                if CollectionStore.shared.recording {
                    CollectionStore.shared.finish(interruption: "训练会话中断")
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
                CollectionStore.shared.finish(interruption: "训练会话中断")
            } else { self.workout = nil }
        }
    }
}
#endif
