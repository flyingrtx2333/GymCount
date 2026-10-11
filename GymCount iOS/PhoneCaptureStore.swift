import Foundation
@preconcurrency import AVFoundation
import WatchConnectivity
import UIKit
import Combine
import HealthKit

@MainActor
final class PhoneCaptureStore: NSObject, ObservableObject, WCSessionDelegate, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var busy = false
    @Published private(set) var uploading = false
    @Published private(set) var recording = false
    @Published private(set) var starting = false
    @Published private(set) var count = 0
    @Published private(set) var message = ""
    @Published private(set) var history: [VideoCaptureManifest] = []
    @Published private(set) var cameraReady = false
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

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func videoURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("video.mov") }
    func sensorURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("motion.json") }
    private func save(_ manifest: VideoCaptureManifest) {
        do {
            try FileManager.default.createDirectory(at: folder(manifest.id), withIntermediateDirectories: true)
            try JSONEncoder().encode(manifest).write(to: folder(manifest.id).appendingPathComponent("manifest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            reload()
        } catch { message = "记录保存失败，请保留应用并检查存储空间" }
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
            await stop(reason: "已离开采集工具，本组采集结束")
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
        guard permitted else { message = "请在系统设置中允许相机权限"; return }
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CaptureError.text("相机不可用") }
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
                        session.commitConfiguration(); continuation.resume(throwing: CaptureError.text("无法配置录像")); return
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
        busy = true; starting = true; message = "正在连接手表…"
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
                await self.cancelStart(reason: "连接超时，请打开手表采集页后重试")
            }
        }
        do {
            try await wakeWatchIfNeeded(generation: generation)
            guard generation == commandGeneration, captureScreenToken != nil else { return }
            var ready = try await request(["command": "prepare", "exercise": exercise])
            if ready["authorizationPending"] as? Bool == true {
                // Human authorization has its own bounded wait, outside the connection deadline.
                watchdog?.invalidate(); watchdog = nil
                message = "请在手机或手表上授权"
                for _ in 0..<60 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    guard generation == commandGeneration, captureScreenToken != nil else { return }
                    ready = try await request(["command": "prepare", "exercise": exercise])
                    if ready["ready"] as? Bool == true { break }
                }
                guard generation == commandGeneration, captureScreenToken != nil else { return }
                guard ready["ready"] as? Bool == true else { throw CaptureError.text("授权未完成，请确认系统授权后重试") }
                watchdog = Timer.scheduledTimer(withTimeInterval: startTimeout, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.commandGeneration == generation, self.starting else { return }
                        await self.cancelStart(reason: "连接超时，请重试")
                    }
                }
            }
            guard generation == commandGeneration, captureScreenToken != nil else { return }
            guard ready["ready"] as? Bool == true else { throw CaptureError.text("手表未就绪，请打开手表采集页后重试") }
            var best: (offset: Double, rtt: Double)?
            message = "正在准备采集…"
            for _ in 0..<5 {
                let sent = Date().timeIntervalSince1970
                let response = try await request(["command": "ping"])
                guard generation == commandGeneration, captureScreenToken != nil else { return }
                let received = Date().timeIntervalSince1970
                guard let watchReceived = response["received"] as? Double, let watchSent = response["sent"] as? Double else { throw CaptureError.text("手表校时失败") }
                let reading = CaptureClockReading(phoneSent: sent, watchReceived: watchReceived, watchSent: watchSent, phoneReceived: received)
                let rtt = reading.roundTrip
                let offset = reading.offset
                if best == nil || rtt < best!.rtt { best = (offset, rtt) }
            }
            guard generation == commandGeneration, captureScreenToken != nil else { return }
            guard let best, best.rtt < 1 else { throw CaptureError.text("手表连接延迟过高，请靠近手机后重试") }
            let id = UUID()
            active = VideoCaptureManifest(id: id, exercise: exercise, createdAt: Date(), watchClockOffset: best.offset, clockRoundTrip: best.rtt)
            count = 0; save(active!)
            UIApplication.shared.isIdleTimerDisabled = true
            message = "正在准备采集…"
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

    func cancelStart(reason: String = "已取消，可重新开始") async {
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
            if starting { await cancelStart(reason: reason ?? "已取消，可重新开始") }
            return
        }
        starting = false
        commandGeneration = UUID(); busy = true; watchdog?.invalidate(); watchdog = nil
        // Keep recording through the Watch stop acknowledgement so its final samples are on video.
        do { _ = try await request(["command": "stop", "id": current.id.uuidString]) }
        catch { active?.error = "手表结束未确认；可在记录页重试接收数据" }
        if let reason { active?.error = reason }
        if let active { save(active) }
        if movie.isRecording { movie.stopRecording() }
        else { active = nil; busy = false; recording = false; UIApplication.shared.isIdleTimerDisabled = false }
    }

    func receiveAgain(_ id: UUID) async {
        do { _ = try await request(["command": "stop", "id": id.uuidString]); message = "正在接收采样…" }
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
        guard var item = history.first(where: { $0.id == id }), item.sensorComplete, item.actualCount != nil else {
            message = "请先收到采样并填写实际次数"; return
        }
        uploading = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer { uploading = false; UIApplication.shared.isIdleTimerDisabled = recording }
        message = "正在上传采样…"
        watchFeedback("upload", message: message)
        do {
            let confirmedSensor = folder(id).appendingPathComponent("uploaded-motion.json")
            let sensorData = try Data(contentsOf: FileManager.default.fileExists(atPath: confirmedSensor.path) ? confirmedSensor : sensorURL(id))
            let uploadedCount = ((try JSONSerialization.jsonObject(with: sensorData)) as? [String: Any])?["actual_count"] as? Int
            let data = try await CaptureCloudUpload.post("sessions", body: sensorData)
            let reply = try JSONDecoder().decode(CaptureCloudUpload.SensorReply.self, from: data)
            guard reply.session_id == id else { throw CaptureError.text("采样关联失败，请重试") }
            try sensorData.write(to: confirmedSensor, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            item.cloudRecordID = reply.id; save(item)
            guard item.videoComplete else { throw CaptureError.text("采样已上传，录像尚未保存完整") }
            message = "正在上传录像…"
            try await CaptureCloudUpload.uploadVideo(file: videoURL(id), manifest: item, sensor: reply)
            item.cloudVideoUploadedAt = Date(); save(item)
            message = uploadedCount == item.actualCount ? "上传成功" : "已上传；请在网站将次数改为 \(item.actualCount ?? 0)"
            watchFeedback("success", message: "上传完成")
        } catch {
            message = item.cloudRecordID == nil ? error.localizedDescription : "采样已上传，录像未完成：\(error.localizedDescription)"
            watchFeedback("failure", message: message)
        }
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
        guard HKHealthStore.isHealthDataAvailable() else { throw CaptureError.text("这台手机无法使用健康权限") }
        let workout = HKObjectType.workoutType()
        if health.authorizationStatus(for: workout) == .sharingAuthorized { return }
        message = "请确认体能训练授权…"
        try await health.requestAuthorization(toShare: [workout], read: [])
        guard health.authorizationStatus(for: workout) == .sharingAuthorized else {
            throw CaptureError.text("体能训练未获授权；若此前拒绝，请在健康中开启体能训练写入")
        }
    }

    private func wakeWatchIfNeeded(generation: UUID) async throws {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--capture-start-timeout-test") { return }
        #endif
        if WCSession.default.activationState == .activated, WCSession.default.isReachable { return }
        message = "正在打开手表采集页…"
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let _: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate(continuation)
            health.startWatchApp(with: configuration) { success, _ in
                if success { gate.finish(.success([:])) }
                else { gate.finish(.failure(CaptureError.text("未能打开手表应用，请确认已安装并完成体能训练授权"))) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                gate.finish(.failure(CaptureError.text("打开手表超时，请抬腕查看后重试")))
            }
        }
        for _ in 0..<50 {
            guard generation == commandGeneration, captureScreenToken != nil else { throw CancellationError() }
            if WCSession.default.activationState == .activated, WCSession.default.isReachable { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CaptureError.text("手表已收到打开请求，但连接尚未就绪，请重试")
    }

    private func request(_ payload: [String: Any]) async throws -> [String: Any] {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--capture-start-timeout-test") {
            // Reproduce a readiness reply arriving after the whole-start deadline.
            try await Task.sleep(nanoseconds: 8_000_000_000)
            return ["ready": true]
        }
        #endif
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { throw CaptureError.text("请打开配套手表应用，并让手机与手表保持连接") }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate(continuation)
            WCSession.default.sendMessage(payload, replyHandler: { response in
                if let error = response["error"] as? String { gate.finish(.failure(CaptureError.text(error))) }
                else { gate.finish(.success(response)) }
            }, errorHandler: { gate.finish(.failure($0)) })
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { gate.finish(.failure(CaptureError.text("手表响应超时"))) }
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
                self.message = "正在准备采集…"
                _ = try await self.request(["command": "start", "id": item.id.uuidString, "exercise": item.exercise])
                guard self.active?.id == item.id, self.commandGeneration == generation, self.movie.isRecording else {
                    _ = try? await self.request(["command": "stop", "id": item.id.uuidString]); return
                }
                self.busy = false; self.starting = false; self.recording = true; self.watchdog?.invalidate()
                self.message = "采集中"
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
            if !successful { item.error = "录像未完整保存，请检查空间或相机中断" }
            self.active = item; self.save(item)
            self.recording = false; self.busy = true; self.watchdog?.invalidate()
            UIApplication.shared.isIdleTimerDisabled = false
            // Camera/system termination must also stop Watch sampling.
            _ = try? await self.request(["command": "stop", "id": item.id.uuidString])
            self.message = item.error ?? "录像已保存，等待采样"
            self.active = nil
            self.busy = false
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor in self.status(message) } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            guard message["command"] as? String == "startFromWatch", let exercise = message["exercise"] as? String,
                  ["squat", "bench_press", "deadlift", "bicep_curl", "rest", "walking", "other"].contains(exercise),
                  self.captureScreenToken != nil, self.cameraReady, UIApplication.shared.applicationState == .active, !self.busy, !self.recording else {
                replyHandler(["error": "请先在手机打开设置 → 开发者工具 → 同步录像与采样"]); return
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
                self.save(item); self.message = "已保存"
            } catch { self.message = "手表采样保存失败，请重试接收" }
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
