import Foundation
@preconcurrency import AVFoundation
import WatchConnectivity
import UIKit
import Combine
import HealthKit

enum WorkoutSyncState: Equatable {
    case idle, connecting, unpaired, notInstalled, waiting, receiving, succeeded, failed
    var title: String { switch self {
        case .idle: String(localized: "手表同步")
        case .connecting: String(localized: "正在连接手表…")
        case .unpaired: String(localized: "尚未配对手表")
        case .notInstalled: String(localized: "请安装手表应用")
        case .waiting: String(localized: "等待手表连接")
        case .receiving: String(localized: "正在接收记录")
        case .succeeded: String(localized: "已同步")
        case .failed: String(localized: "同步失败")
    } }
    var symbol: String { switch self {
        case .succeeded: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .connecting, .receiving: "arrow.triangle.2.circlepath"
        default: "applewatch"
    } }
}

enum WatchSetupState: Equatable {
    case checking, unpaired, notInstalled, ready
}

enum CaptureSampleReceiveState: Equatable {
    case receiving(UUID), succeeded, failed(String)
    var isReceiving: Bool { if case .receiving = self { true } else { false } }
    var message: String { switch self {
        case .receiving: String(localized: "正在接收采样…")
        case .succeeded: String(localized: "采样已接收")
        case .failed(let message): message
    } }
}

@MainActor
final class PhoneCaptureStore: NSObject, ObservableObject, WCSessionDelegate, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var busy = false
    @Published private(set) var uploading = false
    @Published private(set) var uploadStatus: CaptureUploadStatus?
    @Published var completedCaptureID: UUID?
    @Published private(set) var recording = false
    @Published private(set) var starting = false
    @Published private(set) var count = 0
    @Published private(set) var message = ""
    @Published private(set) var history: [VideoCaptureManifest] = []
    @Published private(set) var cameraReady = false
    @Published private(set) var cameraDevice: AVCaptureDevice?
    @Published private(set) var benchReviews: [UUID: BenchAnalysis] = [:]
    @Published private(set) var sampleReceiveStates: [UUID: CaptureSampleReceiveState] = [:]
    @Published private(set) var actualCountErrors: [UUID: String] = [:]
    @Published private(set) var workoutSyncMessage = ""
    @Published private(set) var workoutSyncState = WorkoutSyncState.idle {
        didSet {
            if workoutSyncState != .receiving && workoutSyncState != .connecting { workoutActivity.cancelTimeout() }
        }
    }
    @Published private(set) var watchSetupState = WatchSetupState.checking
    @Published private(set) var unavailableTimelineIDs: Set<UUID> = []
    private let workoutStore: PhoneWorkoutStore?
    nonisolated private let workoutInbox: URL
    nonisolated private let workoutReceiverID: String
    private let connectivityEnabled: Bool
    private let workoutActivity = WorkoutSyncActivity()
    private var workoutRequestGeneration = UUID()
    let camera = AVCaptureSession()
    private let health = HKHealthStore()
    private let movie = AVCaptureMovieFileOutput()
    private let cameraQueue = DispatchQueue(label: "GymCount.camera")
    private var captureRotation: AVCaptureDevice.RotationCoordinator?
    private var active: VideoCaptureManifest?
    private var watchdog: Timer?
    private var configuring = false
    private var commandGeneration = UUID()
    private var captureScreenToken: UUID?
    private var lastCaptureStatus: [UUID: NSDictionary] = [:]
    private let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoCaptures", isDirectory: true)

    init(workoutStore: PhoneWorkoutStore? = nil, defaults: UserDefaults = .standard, activateConnectivity: Bool = true) {
        self.workoutStore = workoutStore
        workoutInbox = (workoutStore?.snapshotURL.deletingLastPathComponent() ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).appendingPathComponent("IncomingWorkouts")
        workoutReceiverID = defaults.string(forKey: "watchSync.receiverID.v2") ?? UUID().uuidString
        defaults.set(workoutReceiverID, forKey: "watchSync.receiverID.v2")
        connectivityEnabled = activateConnectivity
        super.init()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        if activateConnectivity && WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    func requestWorkoutHistory(force: Bool = false, timelineID: UUID? = nil) {
        guard connectivityEnabled, workoutStore != nil, WCSession.isSupported() else { return }
        if force {
            Task { @MainActor in await self.drainWorkoutInbox(); await self.drainTimelineInbox() }
        }
        refreshWatchSetup()
        if timelineID == nil && !force && (workoutSyncState == .receiving || workoutSyncState == .connecting) { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            let generation = UUID(); workoutRequestGeneration = generation
            workoutSyncState = .connecting; workoutSyncMessage = workoutSyncState.title
            session.activate(); scheduleWorkoutTimeout(generation); return
        }
        guard session.isPaired else { workoutSyncState = .unpaired; workoutSyncMessage = workoutSyncState.title; return }
        guard session.isWatchAppInstalled else { workoutSyncState = .notInstalled; workoutSyncMessage = workoutSyncState.title; return }
        guard workoutActivity.beginRequest(force: force || timelineID != nil) else { return }
        let generation = UUID(); workoutRequestGeneration = generation
        var payload: [String: Any] = ["kind": WorkoutSync.requestKind, "receiver_id": workoutReceiverID,
                                      "timeline_version": 1, "workout_report_version": 1, WorkoutReportSensors.capabilityKey: 1,
                                      WorkoutSync.exerciseCapabilityKey: ExerciseType.allCases.map(\.rawValue), "force": force]
        if let timelineID { payload["timeline_id"] = timelineID.uuidString; unavailableTimelineIDs.remove(timelineID) }
        let pending = session.outstandingUserInfoTransfers.filter { $0.userInfo["kind"] as? String == WorkoutSync.requestKind }
        if force { pending.forEach { $0.cancel() } }
        if force || pending.isEmpty { session.transferUserInfo(payload) }
        // Reachability is for live messages; background transfers can keep
        // receiving while the Watch app is not reachable.
        workoutSyncState = session.isReachable ? .connecting : .waiting
        workoutSyncMessage = workoutSyncState.title
        scheduleWorkoutTimeout(generation)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self, self.workoutRequestGeneration == generation else { return }
                    if self.handleTimelineFailure(reply) { return }
                    if reply["exercise_update_required"] as? Bool == true {
                        self.workoutSyncState = .failed
                        self.workoutSyncMessage = String(localized: "请更新手机 App 以同步新增动作")
                        return
                    }
                    if let timelineID, reply["workout_timeline_id"] as? String == timelineID.uuidString,
                       reply["workout_timeline_available"] as? Bool == false {
                        self.unavailableTimelineIDs.insert(timelineID)
                    }
                    if reply["workout_history_ready"] as? Bool != true {
                        self.workoutSyncState = .failed
                        self.workoutSyncMessage = String(localized: "请先更新手表应用，再同步训练记录")
                    } else if reply["workout_history_pending"] as? Int == 0,
                              (reply["workout_timeline_pending"] as? Int ?? 0) == 0 {
                        let confirmed = await self.workoutStore?.confirmReceivedSync() == true
                        guard self.workoutRequestGeneration == generation else { return }
                        if confirmed {
                            self.workoutSyncState = .succeeded; self.workoutSyncMessage = self.workoutSyncState.title
                        } else { self.workoutSyncState = .failed; self.workoutSyncMessage = self.workoutStore?.storageError ?? String(localized: "记录未能保存，请重试") }
                    }
                }
            }, errorHandler: { _ in
                // The background request is already queued. Only an inactivity
                // deadline may move an active sync back to waiting.
            })
        }
    }

    private func refreshWatchSetup() {
        let session = WCSession.default
        guard session.activationState == .activated else { watchSetupState = .checking; return }
        watchSetupState = !session.isPaired ? .unpaired : !session.isWatchAppInstalled ? .notInstalled : .ready
    }
    private func scheduleWorkoutTimeout(_ generation: UUID) {
        guard workoutSyncState == .receiving || workoutSyncState == .connecting else { return }
        workoutActivity.restartTimeout { [weak self] in
            guard let self, self.workoutRequestGeneration == generation,
                  self.workoutSyncState == .receiving || self.workoutSyncState == .connecting else { return }
            self.workoutSyncState = .waiting; self.workoutSyncMessage = self.workoutSyncState.title
        }
    }

    private func handleTimelineFailure(_ reply: [String: Any]) -> Bool {
        guard reply["workout_timeline_failed"] as? Bool == true else { return false }
        workoutSyncState = .failed
        workoutSyncMessage = String(localized: "训练时间轴接收失败，请重试同步")
        return true
    }

    private func receiveWorkoutHistory(_ payload: [String: Any]) async -> [String: Any]? {
        guard [WorkoutSync.batchKind, WorkoutSync.reportFileKind].contains(payload["kind"] as? String ?? "") else { return nil }
        do {
            guard let workoutStore else { throw WorkoutSync.Failure.invalidPayload }
            if payload["kind"] as? String == WorkoutSync.reportFileKind {
                guard payload["receiver_id"] as? String == workoutReceiverID else {
                    throw WorkoutSync.Failure.invalidPayload
                }
            }
            let records = try WorkoutSync.decode(payload)
            try await workoutStore.receiveWatchHistory(records)
            workoutRequestGeneration = UUID()
            if workoutSyncState != .receiving { workoutSyncState = .receiving }
            scheduleWorkoutTimeout(workoutRequestGeneration)
            let progress = String(localized: "已接收 \(records.count) 条手表记录")
            if workoutSyncMessage != progress { workoutSyncMessage = progress }
            return ["kind": WorkoutSync.receiptKind, "receiver_id": workoutReceiverID,
                    "workout_report_version": 1, "ids": records.map { $0.id.uuidString }]
        } catch {
            workoutSyncState = .failed
            workoutSyncMessage = String(localized: "手表记录保存失败，原记录仍保留在手表，请稍后重试")
            return ["error": workoutSyncMessage]
        }
    }

    private func queueWorkoutReceipt(_ receipt: [String: Any]) {
        guard receipt["kind"] as? String == WorkoutSync.receiptKind else { return }
        let session = WCSession.default
        let ids = WorkoutSync.ids(receipt)
        let exists = session.outstandingUserInfoTransfers.contains {
            $0.userInfo["kind"] as? String == WorkoutSync.receiptKind && WorkoutSync.ids($0.userInfo) == ids
        }
        if !exists { session.transferUserInfo(receipt) }
        if session.isReachable {
            let generation = workoutRequestGeneration
            session.sendMessage(receipt, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self, self.workoutRequestGeneration == generation else { return }
                    if self.handleTimelineFailure(reply) { return }
                    guard reply["workout_history_ready"] as? Bool == true,
                          reply["workout_history_pending"] as? Int == 0,
                          (reply["workout_timeline_pending"] as? Int ?? 0) == 0 else { return }
                    let confirmed = await self.workoutStore?.confirmReceivedSync() == true
                    guard self.workoutRequestGeneration == generation else { return }
                    if confirmed {
                        self.workoutSyncState = .succeeded; self.workoutSyncMessage = self.workoutSyncState.title
                    } else { self.workoutSyncState = .failed; self.workoutSyncMessage = self.workoutStore?.storageError ?? String(localized: "记录未能保存，请重试") }
                }
            }, errorHandler: nil)
        }
        Task { @MainActor in await self.drainTimelineInbox() }
    }

    private func receiveWorkoutTimeline(_ file: URL, metadata: [String: Any]) async -> Bool {
        do {
            guard let workoutStore,
                  let text = metadata["id"] as? String, let id = UUID(uuidString: text),
                  metadata["receiver_id"].map({ ($0 as? String) == workoutReceiverID }) ?? true else {
                throw WorkoutSync.Failure.invalidPayload
            }
            // Tombstoned records are intentionally discarded and acknowledged.
            // Every other receipt follows successful atomic persistence.
            let isReportSensor = metadata["kind"] as? String == WorkoutReportSensors.fileKind
            var receipt: [String: Any] = ["kind": isReportSensor ? WorkoutReportSensors.receiptKind : WorkoutTimeline.receiptKind,
                "receiver_id": workoutReceiverID, "ids": [id.uuidString]]
            if isReportSensor {
                guard metadata["receiver_id"] as? String == workoutReceiverID,
                      let parentText = metadata["workout_id"] as? String,
                      let parentID = UUID(uuidString: parentText) else { throw WorkoutSync.Failure.invalidPayload }
                try await workoutStore.receiveWatchReportSensorFile(file, workoutID: parentID, segmentID: id)
                receipt["workout_id"] = parentID.uuidString
                unavailableTimelineIDs.remove(parentID)
            } else {
                try await workoutStore.receiveWatchTimelineFile(file, id: id)
                unavailableTimelineIDs.remove(id)
            }
            workoutSyncState = .receiving; workoutSyncMessage = workoutSyncState.title
            scheduleWorkoutTimeout(workoutRequestGeneration)
            let session = WCSession.default
            let queued = session.outstandingUserInfoTransfers.contains {
                $0.userInfo["kind"] as? String == receipt["kind"] as? String && WorkoutSync.ids($0.userInfo) == [id] &&
                    $0.userInfo["workout_id"] as? String == receipt["workout_id"] as? String
            }
            if !queued { session.transferUserInfo(receipt) }
            if session.isReachable {
                let generation = workoutRequestGeneration
                session.sendMessage(receipt, replyHandler: { [weak self] reply in
                    Task { @MainActor in
                        guard let self, self.workoutRequestGeneration == generation else { return }
                        if self.handleTimelineFailure(reply) { return }
                        guard reply["workout_history_ready"] as? Bool == true,
                              reply["workout_history_pending"] as? Int == 0,
                              (reply["workout_timeline_pending"] as? Int ?? 0) == 0 else { return }
                        let confirmed = await self.workoutStore?.confirmReceivedSync() == true
                        guard self.workoutRequestGeneration == generation else { return }
                        if confirmed {
                            self.workoutSyncState = .succeeded; self.workoutSyncMessage = self.workoutSyncState.title
                        } else {
                            self.workoutSyncState = .failed
                            self.workoutSyncMessage = self.workoutStore?.storageError ?? String(localized: "记录未能保存，请重试")
                        }
                    }
                }, errorHandler: nil)
            }
            return true
        } catch {
            workoutSyncState = .failed
            workoutSyncMessage = String(localized: "训练时间轴保存失败，请重试同步")
            return false
        }
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func videoURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("video.mov") }
    func sensorURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("motion.json") }
    func canDeleteCapture(_ id: UUID) -> Bool { !uploading && active?.id != id && sampleReceiveStates[id]?.isReceiving != true }
    func deleteCapture(_ id: UUID) throws {
        guard history.contains(where: { $0.id == id }) else { return }
        guard canDeleteCapture(id) else {
            throw CaptureError.text(String(localized: "请在采集或上传结束后再删除"))
        }
        do { try FileManager.default.removeItem(at: folder(id)) }
        catch {
            reload()
            throw CaptureError.text(String(localized: "删除采集记录失败，请稍后重试"))
        }
        lastCaptureStatus.removeValue(forKey: id)
        benchReviews.removeValue(forKey: id)
        sampleReceiveStates.removeValue(forKey: id)
        actualCountErrors.removeValue(forKey: id)
        reload()
    }
    func reviewBench(_ id: UUID) async {
        guard history.first(where: { $0.id == id })?.exercise == "bench_press" else { return }
        let url = sensorURL(id)
        let result = await Task.detached(priority: .utility) { () -> BenchAnalysis? in
            struct Input: Decodable {
                struct Point: Decodable { let t: Double }
                let motion_samples: [BenchMotionSample]
                let samples: [Point]
                let duration_seconds: Double
            }
            guard let data = try? Data(contentsOf: url),
                  let input = try? JSONDecoder().decode(Input.self, from: data) else { return nil }
            guard let first = input.motion_samples.first, let last = input.motion_samples.last,
                  let origin = input.samples.first?.t,
                  first.t - origin <= 0.25, origin + input.duration_seconds - last.t <= 0.25 else {
                var result = BenchAnalysis(); result.status = "insufficient_data"; return result
            }
            return BenchPressAnalysis.analyze(input.motion_samples)
        }.value
        // A separate local review never rewrites the original Watch result,
        // video labels, uploaded payload/hash, or historical actual_count.
        guard history.contains(where: { $0.id == id }) else { return }
        benchReviews[id] = result
    }
    @discardableResult
    private func save(_ manifest: VideoCaptureManifest) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder(manifest.id), withIntermediateDirectories: true)
            try JSONEncoder().encode(manifest).write(to: folder(manifest.id).appendingPathComponent("manifest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            if let index = history.firstIndex(where: { $0.id == manifest.id }) { history[index] = manifest }
            else { history.append(manifest); history.sort { $0.createdAt > $1.createdAt } }
            return true
        } catch { message = String(localized: "记录保存失败，请保留应用并检查存储空间"); return false }
    }
    private func reload() {
        let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        history = directories.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("manifest.json")) else { return nil }
            return try? JSONDecoder().decode(VideoCaptureManifest.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func enterCaptureScreen() async {
        let token = UUID(); captureScreenToken = token
        while configuring {
            guard captureScreenToken == token else { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard captureScreenToken == token else { return }
        await configureCamera(token: token)
    }

    func leaveCaptureScreen() {
        captureScreenToken = nil
        cameraReady = false
        cameraDevice = nil
        captureRotation = nil
        commandGeneration = UUID()
        if active == nil { busy = false; starting = false; watchdog?.invalidate(); watchdog = nil }
        if movie.isRecording { movie.stopRecording() }
        let session = camera
        cameraQueue.async { session.stopRunning() }
        Task {
            await stop(reason: String(localized: "已离开采集工具，本组采集结束"))
        }
    }

    private func configureCamera(token: UUID) async {
        guard !cameraReady, !configuring else { return }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--capture-start-timeout-test") {
            cameraReady = true
            return
        }
        #endif
        configuring = true; defer { configuring = false }
        let permitted = await AVCaptureDevice.requestAccess(for: .video)
        guard captureScreenToken == token else { return }
        guard permitted else { message = String(localized: "请在系统设置中允许相机权限"); return }
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CaptureError.text(String(localized: "相机不可用")) }
            let input = try AVCaptureDeviceInput(device: device)
            let session = camera, output = movie
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                cameraQueue.async {
                    if !session.inputs.isEmpty {
                        session.startRunning(); continuation.resume(); return
                    }
                    session.beginConfiguration()
                    session.sessionPreset = .hd1280x720
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration(); continuation.resume(throwing: CaptureError.text(String(localized: "无法配置录像"))); return
                    }
                    session.addInput(input); session.addOutput(output)
                    output.maxRecordedDuration = CMTime(seconds: 185, preferredTimescale: 600)
                    session.commitConfiguration(); session.startRunning()
                    continuation.resume()
                }
            }
            guard captureScreenToken == token else {
                let session = camera
                cameraQueue.async { session.stopRunning() }
                return
            }
            cameraDevice = (camera.inputs.first as? AVCaptureDeviceInput)?.device
            captureRotation = cameraDevice.map { AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: nil) }
            cameraReady = true
        } catch { message = error.localizedDescription }
    }

    func start(exercise: String) async {
        guard !busy, !recording, cameraReady, captureScreenToken != nil else { return }
        busy = true; starting = true; message = String(localized: "正在连接手表…")
        let generation = UUID(); commandGeneration = generation
        watchdog?.invalidate()
        do {
            try await authorizeCaptureOnPhone()
        } catch {
            guard generation == commandGeneration else { return }
            busy = false; starting = false; message = error.localizedDescription
            return
        }
        guard generation == commandGeneration, captureScreenToken != nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: startTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.commandGeneration == generation, self.starting else { return }
                await self.cancelStart(reason: String(localized: "连接超时，请打开手表采集页后重试"))
            }
        }
        do {
            try await wakeWatchIfNeeded(generation: generation)
            guard generation == commandGeneration, captureScreenToken != nil else { return }
            var ready = try await request(["command": "prepare", "exercise": exercise])
            if ready["authorizationPending"] as? Bool == true {
                // Human authorization has its own bounded wait, outside the connection deadline.
                watchdog?.invalidate(); watchdog = nil
                message = String(localized: "请在手机或手表上授权")
                for _ in 0..<60 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    guard generation == commandGeneration, captureScreenToken != nil else { return }
                    ready = try await request(["command": "prepare", "exercise": exercise])
                    if ready["ready"] as? Bool == true { break }
                }
                guard generation == commandGeneration, captureScreenToken != nil else { return }
                guard ready["ready"] as? Bool == true else { throw CaptureError.text(String(localized: "授权未完成，请确认系统授权后重试")) }
                watchdog = Timer.scheduledTimer(withTimeInterval: startTimeout, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.commandGeneration == generation, self.starting else { return }
                        await self.cancelStart(reason: String(localized: "连接超时，请重试"))
                    }
                }
            }
            guard generation == commandGeneration, captureScreenToken != nil else { return }
            guard ready["ready"] as? Bool == true else { throw CaptureError.text(String(localized: "手表未就绪，请打开手表采集页后重试")) }
            var best: (offset: Double, rtt: Double)?
            message = String(localized: "正在准备采集…")
            for _ in 0..<5 {
                let sent = Date().timeIntervalSince1970
                let response = try await request(["command": "ping"])
                guard generation == commandGeneration, captureScreenToken != nil else { return }
                let received = Date().timeIntervalSince1970
                guard let watchReceived = response["received"] as? Double, let watchSent = response["sent"] as? Double else { throw CaptureError.text(String(localized: "手表校时失败")) }
                let reading = CaptureClockReading(phoneSent: sent, watchReceived: watchReceived, watchSent: watchSent, phoneReceived: received)
                let rtt = reading.roundTrip
                let offset = reading.offset
                if best == nil || rtt < best!.rtt { best = (offset, rtt) }
            }
            guard generation == commandGeneration, captureScreenToken != nil else { return }
            guard let best, best.rtt < 1 else { throw CaptureError.text(String(localized: "手表连接延迟过高，请靠近手机后重试")) }
            let id = UUID()
            active = VideoCaptureManifest(id: id, exercise: exercise, createdAt: Date(), watchClockOffset: best.offset, clockRoundTrip: best.rtt)
            count = 0; save(active!)
            UIApplication.shared.isIdleTimerDisabled = true
            message = String(localized: "正在准备采集…")
            // Capture keeps its starting orientation; the preview can continue adapting.
            if let angle = captureRotation?.videoRotationAngleForHorizonLevelCapture,
               let connection = movie.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            movie.startRecording(to: videoURL(id), recordingDelegate: self)
        } catch {
            if generation == commandGeneration {
                watchdog?.invalidate(); watchdog = nil
                busy = false; starting = false; message = error.localizedDescription; UIApplication.shared.isIdleTimerDisabled = false
                watchFeedback("failure", message: message)
            }
        }
    }

    private var startTimeout: TimeInterval {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--capture-start-timeout-test") { return 5 }
        #endif
        return 25
    }

    func cancelStart(reason: String = String(localized: "已取消，可重新开始")) async {
        guard starting, !recording else { return }
        if active != nil { await stop(reason: reason); return }
        commandGeneration = UUID()
        watchdog?.invalidate(); watchdog = nil
        busy = false; starting = false; message = reason
        UIApplication.shared.isIdleTimerDisabled = false
        watchFeedback("failure", message: reason)
    }

    func stop(reason: String? = nil) async {
        guard let current = active, recording || busy else {
            if starting { await cancelStart(reason: reason ?? String(localized: "已取消，可重新开始")) }
            return
        }
        starting = false
        commandGeneration = UUID(); busy = true; watchdog?.invalidate(); watchdog = nil
        // Keep recording through the Watch stop acknowledgement so its final samples are on video.
        do { _ = try await request(["command": "stop", "id": current.id.uuidString]) }
        catch { active?.error = String(localized: "手表结束未确认；可在记录页重试接收数据") }
        if let reason { active?.error = reason }
        if let active { save(active) }
        if movie.isRecording { movie.stopRecording() }
        else { active = nil; busy = false; recording = false; UIApplication.shared.isIdleTimerDisabled = false }
    }

    func receiveAgain(_ id: UUID) async {
        guard history.contains(where: { $0.id == id && !$0.sensorComplete }),
              !uploading, sampleReceiveStates[id]?.isReceiving != true else { return }
        let attempt = CaptureSampleReceiveState.receiving(UUID())
        sampleReceiveStates[id] = attempt
        do {
            _ = try await request(["command": "stop", "id": id.uuidString])
            guard sampleReceiveStates[id] == attempt else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.sampleReceiveStates[id] == attempt else { return }
                self.sampleReceiveStates[id] = .failed(String(localized: "采样接收超时，请保持手机与手表连接后重试"))
            }
        } catch {
            guard sampleReceiveStates[id] == attempt else { return }
            sampleReceiveStates[id] = .failed(error.localizedDescription)
        }
    }
    func markReference(_ id: UUID, at seconds: Double) {
        guard var item = history.first(where: { $0.id == id }), seconds.isFinite, seconds >= 0,
              !["rest", "walking", "other"].contains(item.exercise),
              item.referenceEvents.count < 500,
              item.videoDuration.map({ seconds <= $0 }) ?? false,
              item.referenceEvents.last.map({ seconds > $0 + 0.2 }) ?? true else { return }
        item.referenceEvents.append(seconds); item.actualCount = item.referenceEvents.count; save(item)
        setActual(item.referenceEvents.count, for: id)
    }
    func undoReference(_ id: UUID) {
        guard var item = history.first(where: { $0.id == id }), !item.referenceEvents.isEmpty else { return }
        item.referenceEvents.removeLast(); item.actualCount = item.referenceEvents.count; save(item)
        setActual(item.referenceEvents.count, for: id)
    }
    func adjustAlignment(_ id: UUID, by seconds: Double) {
        guard var item = history.first(where: { $0.id == id }) else { return }
        item.alignmentCorrection += seconds; save(item)
    }
    @discardableResult
    func setActual(_ value: Int, for id: UUID) -> Bool {
        let failure = String(localized: "记录保存失败，请保留应用并检查存储空间")
        guard var item = history.first(where: { $0.id == id }) else {
            actualCountErrors[id] = failure
            return false
        }
        let value = ["rest", "walking", "other"].contains(item.exercise) ? 0 : min(500, max(0, value))
        item.actualCount = value
        do {
            // Preserve protocol v2; apply the label only to the local sensor copy.
            let sensor = sensorURL(id)
            if item.sensorComplete || FileManager.default.fileExists(atPath: sensor.path) {
                let data = try Data(contentsOf: sensor)
                guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw CaptureError.text(failure)
                }
                json["actual_count"] = value
                try JSONSerialization.data(withJSONObject: json).write(to: sensor, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            guard save(item) else {
                actualCountErrors[id] = message
                return false
            }
            actualCountErrors.removeValue(forKey: id)
            return true
        } catch {
            message = failure
            actualCountErrors[id] = failure
            return false
        }
    }
    func upload(_ id: UUID) async {
        guard !uploading else { return }
        let status = CaptureUploadStatus(id: id, stage: .samples)
        uploadStatus = status
        let attemptID = status.attemptID
        guard var item = history.first(where: { $0.id == id }), item.sensorComplete, item.actualCount != nil else {
            message = String(localized: "请先收到采样并填写实际次数")
            uploadStatus?.stage = .failed; uploadStatus?.detail = message
            return
        }
        uploading = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer { uploading = false; UIApplication.shared.isIdleTimerDisabled = recording }
        message = String(localized: "正在上传采样…")
        watchFeedback("upload", message: message)
        do {
            let confirmedSensor = folder(id).appendingPathComponent("uploaded-motion.json")
            let localSensor = sensorURL(id)
            let (sensorData, uploadedCount) = try await WorkoutFileIO.shared.perform { () -> (Data, Int?) in
                let bytes = try Data(contentsOf: FileManager.default.fileExists(atPath: confirmedSensor.path) ? confirmedSensor : localSensor)
                let count = ((try JSONSerialization.jsonObject(with: bytes)) as? [String: Any])?["actual_count"] as? Int
                return (bytes, count)
            }
            let data = try await CaptureCloudUpload.post("sessions", body: sensorData)
            let reply = try JSONDecoder().decode(CaptureCloudUpload.SensorReply.self, from: data)
            guard reply.session_id == id else { throw CaptureError.text(String(localized: "采样关联失败，请重试")) }
            try await WorkoutFileIO.shared.perform { try sensorData.write(to: confirmedSensor, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
            item.cloudRecordID = reply.id; save(item)
            guard item.videoComplete else { throw CaptureError.text(String(localized: "采样已上传，录像尚未保存完整")) }
            message = String(localized: "正在上传录像…")
            try await CaptureCloudUpload.uploadVideo(file: videoURL(id), manifest: item, sensor: reply,
                onStage: { [weak self] stage in
                    guard let self, self.uploading, var status = self.uploadStatus,
                          status.attemptID == attemptID else { return }
                    status.stage = stage; status.progress = stage == .video ? 0 : nil
                    self.uploadStatus = status
                }, onProgress: { [weak self] fraction in
                    guard let self, self.uploading, var status = self.uploadStatus,
                          status.attemptID == attemptID, status.stage == .video else { return }
                    status.progress = max(status.progress ?? 0, fraction)
                    self.uploadStatus = status
                })
            item.cloudVideoUploadedAt = Date(); save(item)
            message = uploadedCount == item.actualCount ? String(localized: "上传成功") : String(localized: "已上传；请在网站将次数改为 \(item.actualCount ?? 0)")
            uploadStatus?.stage = .succeeded; uploadStatus?.progress = 1; uploadStatus?.detail = message
            watchFeedback("success", message: String(localized: "上传完成"))
        } catch {
            message = item.cloudRecordID == nil ? error.localizedDescription : String(localized: "采样已上传，录像未完成：\(error.localizedDescription)")
            uploadStatus?.stage = .failed; uploadStatus?.progress = nil; uploadStatus?.detail = message
            watchFeedback("failure", message: message)
        }
    }

    func dismissUploadStatus(_ id: UUID) {
        guard !uploading, uploadStatus?.id == id else { return }
        uploadStatus = nil
    }

    private func watchFeedback(_ event: String, message: String? = nil) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        var payload = ["command": "feedback", "event": event]
        if let message { payload["message"] = message }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    private func authorizeCaptureOnPhone() async throws {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--capture-start-timeout-test") { return }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { throw CaptureError.text(String(localized: "这台手机无法使用健康权限")) }
        let workout = HKObjectType.workoutType()
        if health.authorizationStatus(for: workout) == .sharingAuthorized { return }
        message = String(localized: "请确认体能训练授权…")
        try await health.requestAuthorization(toShare: [workout], read: [])
        guard health.authorizationStatus(for: workout) == .sharingAuthorized else {
            throw CaptureError.text(String(localized: "体能训练未获授权；若此前拒绝，请在健康中开启体能训练写入"))
        }
    }

    private func wakeWatchIfNeeded(generation: UUID) async throws {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--capture-start-timeout-test") { return }
        #endif
        if WCSession.default.activationState == .activated, WCSession.default.isReachable { return }
        message = String(localized: "正在打开手表采集页…")
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let _: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate(continuation)
            health.startWatchApp(with: configuration) { success, _ in
                if success { gate.finish(.success([:])) }
                else { gate.finish(.failure(CaptureError.text(String(localized: "未能打开手表应用，请确认已安装并完成体能训练授权")))) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                gate.finish(.failure(CaptureError.text(String(localized: "打开手表超时，请抬腕查看后重试"))))
            }
        }
        for _ in 0..<50 {
            guard generation == commandGeneration, captureScreenToken != nil else { throw CancellationError() }
            if WCSession.default.activationState == .activated, WCSession.default.isReachable { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CaptureError.text(String(localized: "手表已收到打开请求，但连接尚未就绪，请重试"))
    }

    private func request(_ payload: [String: Any]) async throws -> [String: Any] {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--capture-start-timeout-test") {
            // Reproduce a readiness reply arriving after the whole-start deadline.
            try await Task.sleep(nanoseconds: 8_000_000_000)
            return ["ready": true]
        }
        #endif
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { throw CaptureError.text(String(localized: "请打开配套手表应用，并让手机与手表保持连接")) }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate(continuation)
            WCSession.default.sendMessage(payload, replyHandler: { response in
                if let error = response["error"] as? String { gate.finish(.failure(CaptureError.text(error))) }
                else { gate.finish(.success(response)) }
            }, errorHandler: { gate.finish(.failure($0)) })
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { gate.finish(.failure(CaptureError.text(String(localized: "手表响应超时")))) }
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let estimatedStart = Date().timeIntervalSince1970 - max(0, CMTimeGetSeconds(output.recordedDuration))
        Task { @MainActor in
            guard var item = self.active, fileURL == self.videoURL(item.id) else { return }
            guard self.captureScreenToken != nil, self.cameraReady else { await self.stop(); return }
            let generation = self.commandGeneration
            item.videoStartedAt = estimatedStart; self.active = item; self.save(item)
            do {
                self.message = String(localized: "正在准备采集…")
                _ = try await self.request(["command": "start", "id": item.id.uuidString, "exercise": item.exercise])
                guard self.active?.id == item.id, self.commandGeneration == generation, self.movie.isRecording else {
                    _ = try? await self.request(["command": "stop", "id": item.id.uuidString]); return
                }
                self.busy = false; self.starting = false; self.recording = true; self.watchdog?.invalidate()
                self.message = String(localized: "采集中")
                self.watchdog = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
                    Task { @MainActor in await self?.stop() }
                }
            } catch { await self.stop(reason: error.localizedDescription) }
        }
    }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let successful = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        Task { @MainActor in
            let duration = (try? await AVURLAsset(url: outputFileURL).load(.duration)).map(CMTimeGetSeconds)
            guard var item = self.active, outputFileURL == self.videoURL(item.id) else { return }
            item.videoDuration = duration.flatMap { $0.isFinite ? $0 : nil }
            item.videoComplete = successful
            if !successful { item.error = String(localized: "录像未完整保存，请检查空间或相机中断") }
            self.active = item; self.save(item)
            self.recording = false; self.busy = true; self.watchdog?.invalidate()
            UIApplication.shared.isIdleTimerDisabled = false
            // Camera/system termination must also stop Watch sampling.
            _ = try? await self.request(["command": "stop", "id": item.id.uuidString])
            let saved = self.history.first(where: { $0.id == item.id }) ?? item
            self.message = saved.error ?? (saved.sensorComplete ? String(localized: "录像与采样已保存，请核对实际次数后上传") : String(localized: "录像已保存，等待采样"))
            self.active = nil
            self.busy = false
            if self.captureScreenToken != nil { self.completedCaptureID = item.id }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if activationState == .activated { self.workoutSyncState = .idle; await self.drainWorkoutInbox(); await self.drainTimelineInbox(); self.requestWorkoutHistory() }
            else if error != nil { self.workoutSyncState = .failed; self.workoutSyncMessage = String(localized: "连接手表失败，请重试") }
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable { self.requestWorkoutHistory() }
        }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshWatchSetup(); self.requestWorkoutHistory() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let receipt = await self.receiveWorkoutHistory(message) { self.queueWorkoutReceipt(receipt); return }
            self.status(message)
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["kind"] as? String == WorkoutSync.batchKind else { return }
        // WC removes a delivered item when this callback returns. Journal its
        // bounded payload first; heavy parsing/merging follows on the file lane.
        do {
            try WorkoutMessageInbox(directory: workoutInbox, receiverID: workoutReceiverID).stage(userInfo)
            Task { @MainActor in await self.drainWorkoutInbox() }
        } catch {
            Task { @MainActor in
                self.workoutSyncState = .failed
                self.workoutSyncMessage = String(localized: "手表记录保存失败，原记录仍保留在手表，请稍后重试")
            }
        }
    }
    private var workoutInboxRevision = 0
    private var drainingInbox = false
    private func drainWorkoutInbox() async {
        workoutInboxRevision &+= 1
        guard !drainingInbox else { return }
        drainingInbox = true; defer { drainingInbox = false }
        let inbox = WorkoutMessageInbox(directory: workoutInbox, receiverID: workoutReceiverID)
        var attempted: Set<URL> = []
        while true {
            let revision = workoutInboxRevision
            let excluded = attempted
            let scan: WorkoutMessageInbox.Scan
            do {
                scan = try await WorkoutFileIO.shared.perform { try inbox.pending(excluding: excluded) }
            } catch {
                workoutSyncState = .failed
                workoutSyncMessage = String(localized: "训练报告接收失败，请重试同步")
                break
            }
            if scan.unreadableFiles > 0 {
                workoutSyncState = .failed
                workoutSyncMessage = String(localized: "训练报告接收失败，请重试同步")
            }
            if scan.entries.isEmpty {
                if revision != workoutInboxRevision { continue }
                break
            }
            for entry in scan.entries {
                attempted.formUnion(entry.files)
                do {
                    guard let receipt = await receiveWorkoutHistory(entry.payload),
                          receipt["kind"] as? String == WorkoutSync.receiptKind else { continue }
                    queueWorkoutReceipt(receipt)
                    try await WorkoutFileIO.shared.perform { try inbox.remove(entry) }
                } catch { workoutSyncState = .failed }
            }
        }
    }
    private var timelineInboxRevision = 0
    private var drainingTimelines = false
    private func drainTimelineInbox() async {
        timelineInboxRevision &+= 1
        guard !drainingTimelines else { return }
        drainingTimelines = true; defer { drainingTimelines = false }
        let directory = workoutInbox.deletingLastPathComponent().appendingPathComponent("IncomingTimelines").appendingPathComponent(workoutReceiverID)
        var attempted: Set<URL> = []
        var attemptedRevision = timelineInboxRevision
        while true {
            let revision = timelineInboxRevision
            if revision != attemptedRevision {
                // A parent may have persisted while this drain was awaiting IO.
                // Retry earlier files once for each new inbox revision.
                attempted.removeAll(); attemptedRevision = revision
            }
            let files = (try? await WorkoutFileIO.shared.perform {
                try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            }) ?? []
            let pending = files.filter { !attempted.contains($0) }
            if pending.isEmpty {
                if revision != timelineInboxRevision { continue }
                break
            }
            for file in pending {
                attempted.insert(file)
                let parts = file.deletingPathExtension().lastPathComponent.split(separator: "_", maxSplits: 1)
                var metadata: [String: Any] = ["receiver_id": workoutReceiverID]
                if parts.count == 2 {
                    guard let parentID = UUID(uuidString: String(parts[0])),
                          let segmentID = UUID(uuidString: String(parts[1].prefix(36))) else { continue }
                    metadata["kind"] = WorkoutReportSensors.fileKind
                    metadata["id"] = segmentID.uuidString; metadata["workout_id"] = parentID.uuidString
                } else {
                    guard let id = UUID(uuidString: String(file.lastPathComponent.prefix(36))) else { continue }
                    metadata["kind"] = WorkoutTimeline.fileKind; metadata["id"] = id.uuidString
                }
                if await receiveWorkoutTimeline(file, metadata: metadata) {
                    try? await WorkoutFileIO.shared.perform { try FileManager.default.removeItem(at: file) }
                }
            }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if let receipt = await self.receiveWorkoutHistory(message) {
                self.queueWorkoutReceipt(receipt); replyHandler(receipt); return
            }
            #if DEBUG
            guard message["command"] as? String == "startFromWatch", let exercise = message["exercise"] as? String,
                  (ExerciseType(rawValue: exercise) != nil || ["rest", "walking", "other"].contains(exercise)),
                  self.captureScreenToken != nil, self.cameraReady, UIApplication.shared.applicationState == .active, !self.busy, !self.recording else {
                replyHandler(["error": String(localized: "请先在手机打开设置 → 开发者工具 → 同步录像与采样")]); return
            }
            // Reply immediately: start() performs its own readiness/clock/start handshake.
            replyHandler(["accepted": true])
            await self.start(exercise: exercise)
            #else
            replyHandler(["error": String(localized: "无效指令")])
            #endif
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor in self.status(applicationContext) } }
    private func status(_ status: [String: Any]) {
        guard let text = status["id"] as? String, let id = UUID(uuidString: text) else { return }
        guard var item = active?.id == id ? active : history.first(where: { $0.id == id }) else { return }
        guard lastCaptureStatus[id] != (status as NSDictionary) else { return }
        if let count = status["count"] as? Int { item.detectedCount = count; if active?.id == id { self.count = count } }
        if let origin = status["sample_origin"] as? Double, origin > 0 { item.sampleOriginOnPhone = origin - item.watchClockOffset }
        if let error = status["error"] as? String { item.error = error }
        if active?.id == id { active = item }
        if save(item) { lastCaptureStatus[id] = status as NSDictionary }
        if status["recording"] as? Bool == false, active?.id == id, recording || busy { Task { await stop() } }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WCSession removes its temporary file after this delegate returns.
        let metadata = file.metadata ?? [:]
        if metadata["kind"] as? String == WorkoutSync.reportFileKind {
            // A transfer from a previous phone installation must not acknowledge
            // this installation's history. The Watch retains and resends its source.
            guard metadata["receiver_id"] as? String == workoutReceiverID else { return }
            do {
                let values = try file.fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size <= WorkoutSync.maximumReportFileBytes + 4096 else { throw WorkoutSync.Failure.invalidPayload }
                guard let payload = try PropertyListSerialization.propertyList(from: Data(contentsOf: file.fileURL),
                    format: nil) as? [String: Any] else { throw WorkoutSync.Failure.invalidPayload }
                try WorkoutMessageInbox(directory: workoutInbox, receiverID: workoutReceiverID).stage(payload)
                Task { @MainActor in await self.drainWorkoutInbox() }
            } catch {
                Task { @MainActor in
                    self.workoutSyncState = .failed
                    self.workoutSyncMessage = String(localized: "训练报告接收失败，请重试同步")
                }
            }
            return
        }
        if [WorkoutTimeline.fileKind, WorkoutReportSensors.fileKind].contains(metadata["kind"] as? String ?? "") {
            do {
                let values = try file.fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size <= WorkoutTimeline.maximumFileBytes,
                      let text = metadata["id"] as? String, let id = UUID(uuidString: text),
                      metadata["receiver_id"].map({ ($0 as? String) == workoutReceiverID }) ?? true else { throw WorkoutSync.Failure.invalidPayload }
                var prefix = id.uuidString
                if metadata["kind"] as? String == WorkoutReportSensors.fileKind {
                    guard metadata["receiver_id"] as? String == workoutReceiverID,
                          let text = metadata["workout_id"] as? String, let parentID = UUID(uuidString: text) else {
                        throw WorkoutSync.Failure.invalidPayload
                    }
                    prefix = parentID.uuidString + "_" + id.uuidString
                }
                let directory = workoutInbox.deletingLastPathComponent().appendingPathComponent("IncomingTimelines").appendingPathComponent(workoutReceiverID)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(prefix + "-" + UUID().uuidString + ".json")
                let staged = directory.appendingPathComponent(".incoming-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: staged) }
                try FileManager.default.copyItem(at: file.fileURL, to: staged)
                try FileManager.default.moveItem(at: staged, to: destination)
                Task { @MainActor in await self.drainTimelineInbox() }
            } catch {
                Task { @MainActor in
                    self.workoutSyncState = .failed
                    self.workoutSyncMessage = String(localized: "训练时间轴接收失败，请重试同步")
                }
            }
            return
        }
        let data = try? Data(contentsOf: file.fileURL)
        Task { @MainActor in
            guard let data, let text = metadata["id"] as? String, let id = UUID(uuidString: text),
                  var item = self.active?.id == id ? self.active : self.history.first(where: { $0.id == id }),
                  var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (json["session_id"] as? String)?.lowercased() == text.lowercased() else { return }
            do {
                if let actual = item.actualCount { json["actual_count"] = actual }
                try JSONSerialization.data(withJSONObject: json).write(to: self.sensorURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                item.sensorComplete = true
                if let error = item.error, [
                    "手表结束未确认；可在记录页重试接收数据",
                    "The Watch did not confirm completion. Retry receiving data from the recording page."
                ].contains(error) { item.error = nil }
                if let origin = metadata["sample_origin"] as? Double, origin > 0 { item.sampleOriginOnPhone = origin - item.watchClockOffset }
                if let detected = json["detected_count"] as? Int { item.detectedCount = detected }
                if self.active?.id == id { self.active = item }
                guard self.save(item) else {
                    self.sampleReceiveStates[id] = .failed(self.message)
                    return
                }
                self.message = String(localized: "已保存")
                self.sampleReceiveStates[id] = .succeeded
                await self.reviewBench(id)
            } catch {
                self.message = String(localized: "手表采样保存失败，请重试接收")
                self.sampleReceiveStates[id] = .failed(self.message)
            }
        }
    }
}

private enum CaptureError: LocalizedError {
    case text(String)
    var errorDescription: String? { if case let .text(text) = self { return text }; return nil }
}
private final class ReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String: Any], Error>?
    init(_ continuation: CheckedContinuation<[String: Any], Error>) { self.continuation = continuation }
    func finish(_ result: Result<[String: Any], Error>) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(with: result)
    }
}
