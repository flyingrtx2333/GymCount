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
    @Published private(set) var benchReviews: [UUID: BenchAnalysis] = [:]
    @Published private(set) var workoutSyncMessage = ""
    @Published private(set) var workoutSyncState = WorkoutSyncState.idle
    private let workoutStore: PhoneWorkoutStore?
    private let workoutReceiverID: String
    private let connectivityEnabled: Bool
    private var workoutRequestGeneration = UUID()
    let camera = AVCaptureSession()
    private let health = HKHealthStore()
    private let movie = AVCaptureMovieFileOutput()
    private let cameraQueue = DispatchQueue(label: "GymCount.camera")
    private var active: VideoCaptureManifest?
    private var watchdog: Timer?
    private var configuring = false
    private var commandGeneration = UUID()
    private var captureScreenToken: UUID?
    private let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoCaptures", isDirectory: true)

    init(workoutStore: PhoneWorkoutStore? = nil, defaults: UserDefaults = .standard, activateConnectivity: Bool = true) {
        self.workoutStore = workoutStore
        workoutReceiverID = defaults.string(forKey: "watchSync.receiverID.v2") ?? UUID().uuidString
        defaults.set(workoutReceiverID, forKey: "watchSync.receiverID.v2")
        connectivityEnabled = activateConnectivity
        super.init()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        if activateConnectivity && WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    func requestWorkoutHistory(force: Bool = false) {
        guard connectivityEnabled, workoutStore != nil, WCSession.isSupported() else { return }
        if !force && (workoutSyncState == .receiving || workoutSyncState == .connecting) { return }
        let session = WCSession.default
        let generation = UUID(); workoutRequestGeneration = generation
        guard session.activationState == .activated else {
            workoutSyncState = .connecting; workoutSyncMessage = workoutSyncState.title
            session.activate(); scheduleWorkoutTimeout(generation); return
        }
        guard session.isPaired else { workoutSyncState = .unpaired; workoutSyncMessage = workoutSyncState.title; return }
        guard session.isWatchAppInstalled else { workoutSyncState = .notInstalled; workoutSyncMessage = workoutSyncState.title; return }
        let payload: [String: Any] = ["kind": WorkoutSync.requestKind, "receiver_id": workoutReceiverID, "force": force]
        let pending = session.outstandingUserInfoTransfers.filter { $0.userInfo["kind"] as? String == WorkoutSync.requestKind }
        if force { pending.forEach { $0.cancel() } }
        if force || pending.isEmpty { session.transferUserInfo(payload) }
        workoutSyncState = session.isReachable ? .receiving : .waiting
        workoutSyncMessage = workoutSyncState.title
        scheduleWorkoutTimeout(generation)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self, self.workoutRequestGeneration == generation else { return }
                    if reply["workout_history_ready"] as? Bool != true {
                        self.workoutSyncState = .failed
                        self.workoutSyncMessage = String(localized: "请先更新手表应用，再同步训练记录")
                    } else if reply["workout_history_pending"] as? Int == 0 {
                        if self.workoutStore?.confirmSync() == true {
                            self.workoutSyncState = .succeeded; self.workoutSyncMessage = self.workoutSyncState.title
                        } else { self.workoutSyncState = .failed; self.workoutSyncMessage = self.workoutStore?.storageError ?? String(localized: "记录未能保存，请重试") }
                    }
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.workoutRequestGeneration == generation else { return }
                    self.workoutSyncState = .waiting; self.workoutSyncMessage = self.workoutSyncState.title
                }
            })
        }
    }
    private func scheduleWorkoutTimeout(_ generation: UUID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, self.workoutRequestGeneration == generation,
                  self.workoutSyncState == .receiving || self.workoutSyncState == .connecting else { return }
            self.workoutSyncState = .waiting; self.workoutSyncMessage = self.workoutSyncState.title
        }
    }

    private func receiveWorkoutHistory(_ payload: [String: Any]) -> [String: Any]? {
        guard payload["kind"] as? String == WorkoutSync.batchKind else { return nil }
        do {
            guard let workoutStore else { throw WorkoutSync.Failure.invalidPayload }
            let records = try WorkoutSync.decode(payload)
            try workoutStore.acceptWatchHistory(records)
            workoutRequestGeneration = UUID()
            workoutSyncState = .receiving
            scheduleWorkoutTimeout(workoutRequestGeneration)
            workoutSyncMessage = String(localized: "已接收 \(records.count) 条手表记录")
            return ["kind": WorkoutSync.receiptKind, "receiver_id": workoutReceiverID,
                    "ids": records.map { $0.id.uuidString }]
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
                    guard let self, self.workoutRequestGeneration == generation,
                          reply["workout_history_ready"] as? Bool == true,
                          reply["workout_history_pending"] as? Int == 0 else { return }
                    if self.workoutStore?.confirmSync() == true {
                        self.workoutSyncState = .succeeded; self.workoutSyncMessage = self.workoutSyncState.title
                    } else { self.workoutSyncState = .failed; self.workoutSyncMessage = self.workoutStore?.storageError ?? String(localized: "记录未能保存，请重试") }
                }
            }, errorHandler: nil)
        } else { workoutSyncState = .waiting }
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func videoURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("video.mov") }
    func sensorURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("motion.json") }
    func canDeleteCapture(_ id: UUID) -> Bool { !uploading && active?.id != id }
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
        benchReviews.removeValue(forKey: id)
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
    private func save(_ manifest: VideoCaptureManifest) {
        do {
            try FileManager.default.createDirectory(at: folder(manifest.id), withIntermediateDirectories: true)
            try JSONEncoder().encode(manifest).write(to: folder(manifest.id).appendingPathComponent("manifest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            reload()
        } catch { message = String(localized: "记录保存失败，请保留应用并检查存储空间") }
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
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
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
        do { _ = try await request(["command": "stop", "id": id.uuidString]); message = String(localized: "正在接收采样…") }
        catch { message = error.localizedDescription }
    }
    func markReference(_ id: UUID, at seconds: Double) {
        guard var item = history.first(where: { $0.id == id }), seconds.isFinite, seconds >= 0,
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
    func setActual(_ value: Int, for id: UUID) {
        guard var item = history.first(where: { $0.id == id }) else { return }
        let value = item.exercise == "other" ? 0 : value
        item.actualCount = value; save(item)
        // Preserve protocol v2; apply label only to the local sensor copy when available.
        if let data = try? Data(contentsOf: sensorURL(id)), var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            json["actual_count"] = value
            if let encoded = try? JSONSerialization.data(withJSONObject: json) { try? encoded.write(to: sensorURL(id), options: .atomic) }
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
            let sensorData = try Data(contentsOf: FileManager.default.fileExists(atPath: confirmedSensor.path) ? confirmedSensor : sensorURL(id))
            let uploadedCount = ((try JSONSerialization.jsonObject(with: sensorData)) as? [String: Any])?["actual_count"] as? Int
            let data = try await CaptureCloudUpload.post("sessions", body: sensorData)
            let reply = try JSONDecoder().decode(CaptureCloudUpload.SensorReply.self, from: data)
            guard reply.session_id == id else { throw CaptureError.text(String(localized: "采样关联失败，请重试")) }
            try sensorData.write(to: confirmedSensor, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
            if activationState == .activated { self.workoutSyncState = .idle; self.requestWorkoutHistory() }
            else if error != nil { self.workoutSyncState = .failed; self.workoutSyncMessage = String(localized: "连接手表失败，请重试") }
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable { self.requestWorkoutHistory() }
            else if self.workoutSyncState == .receiving { self.workoutSyncState = .waiting; self.workoutSyncMessage = self.workoutSyncState.title }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let receipt = self.receiveWorkoutHistory(message) { self.queueWorkoutReceipt(receipt); return }
            self.status(message)
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if let receipt = self.receiveWorkoutHistory(userInfo) { self.queueWorkoutReceipt(receipt) }
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    if let receipt = self.receiveWorkoutHistory(userInfo) { self.queueWorkoutReceipt(receipt) }
                }
            }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if let receipt = self.receiveWorkoutHistory(message) {
                self.queueWorkoutReceipt(receipt); replyHandler(receipt); return
            }
            guard message["command"] as? String == "startFromWatch", let exercise = message["exercise"] as? String,
                  ["squat", "bench_press", "deadlift", "bicep_curl", "rest", "walking", "other"].contains(exercise),
                  self.captureScreenToken != nil, self.cameraReady, UIApplication.shared.applicationState == .active, !self.busy, !self.recording else {
                replyHandler(["error": String(localized: "请先在手机打开设置 → 开发者工具 → 同步录像与采样")]); return
            }
            // Reply immediately: start() performs its own readiness/clock/start handshake.
            replyHandler(["accepted": true])
            await self.start(exercise: exercise)
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor in self.status(applicationContext) } }
    private func status(_ status: [String: Any]) {
        guard let text = status["id"] as? String, let id = UUID(uuidString: text) else { return }
        guard var item = active?.id == id ? active : history.first(where: { $0.id == id }) else { return }
        if let count = status["count"] as? Int { item.detectedCount = count; if active?.id == id { self.count = count } }
        if let origin = status["sample_origin"] as? Double, origin > 0 { item.sampleOriginOnPhone = origin - item.watchClockOffset }
        if let error = status["error"] as? String { item.error = error }
        if active?.id == id { active = item }
        save(item)
        if status["recording"] as? Bool == false, active?.id == id, recording || busy { Task { await stop() } }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WCSession removes its temporary file after this delegate returns.
        let data = try? Data(contentsOf: file.fileURL)
        let metadata = file.metadata ?? [:]
        Task { @MainActor in
            guard let data, let text = metadata["id"] as? String, let id = UUID(uuidString: text),
                  var item = self.active?.id == id ? self.active : self.history.first(where: { $0.id == id }),
                  var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (json["session_id"] as? String)?.lowercased() == text.lowercased() else { return }
            do {
                if let actual = item.actualCount { json["actual_count"] = actual }
                try JSONSerialization.data(withJSONObject: json).write(to: self.sensorURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                item.sensorComplete = true
                if let origin = metadata["sample_origin"] as? Double, origin > 0 { item.sampleOriginOnPhone = origin - item.watchClockOffset }
                if let detected = json["detected_count"] as? Int { item.detectedCount = detected }
                if self.active?.id == id { self.active = item }
                self.save(item); self.message = String(localized: "已保存")
                await self.reviewBench(id)
            } catch { self.message = String(localized: "手表采样保存失败，请重试接收") }
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
