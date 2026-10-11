#if DEBUG || GYMCOUNT_CAPTURE
import SwiftUI
import CoreMotion
import WatchKit
import Darwin
import OSLog

struct CaptureSample: Encodable {
    let t: Double
    let received_t: Double
    let x: Double
    let y: Double
    let z: Double
}

struct CaptureVector: Encodable {
    let x: Double
    let y: Double
    let z: Double
}

struct CaptureQuaternion: Encodable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

struct CaptureMotion: Encodable {
    let t: Double
    let received_t: Double
    let gravity: CaptureVector
    let user_acceleration: CaptureVector
    let rotation_rate: CaptureVector
    let attitude: CaptureVector // roll, pitch, yaw in radians
    let quaternion: CaptureQuaternion
    let magnetic_field: CaptureVector
    let magnetic_field_accuracy: Int
    let heading: Double
}

struct CaptureAvailability: Encodable {
    let gyroscope: Bool
    let device_motion: Bool
    let magnetometer: Bool
}

struct CaptureRecord: Encodable {
    let schema_version = 2
    let session_id: UUID
    let started_at: Date
    let exercise: String
    var actual_count: Int
    let detected_count: Int
    let duration_seconds: Double
    let sample_rate_hz = 40.0
    let acceleration_unit = "g"
    let rotation_unit = "rad/s"
    let attitude_unit = "rad"
    let magnetic_field_unit = "uT"
    let attitude_reference_frame = "xArbitraryZVertical"
    let wrist: String
    let watch_crown: String
    let pace: String
    let watch_model: String
    let os_version: String
    let app_version: String
    let algorithm_version: String
    let participant_id: UUID
    var notes: String
    let samples: [CaptureSample]
    let gyroscope_samples: [CaptureSample]
    let motion_samples: [CaptureMotion]
    let magnetometer_samples: [CaptureSample]
    let sensor_availability: CaptureAvailability
    let detected_events: [Double]
    let reference_events_truncated: Bool
}

// Independent streams retain sensor timestamps; never align them by callback order.
private final class RawCapture {
    private let lock = NSLock()
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var origin: Double?
    private let wallAnchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    var originWallTime: Double? {
        lock.lock(); defer { lock.unlock() }
        return origin.map { wallAnchor + $0 }
    }
    private var points: [CaptureSample] = []
    private var gyro: [CaptureSample] = []
    private var deviceMotion: [CaptureMotion] = []
    private var magnetometer: [CaptureSample] = []
    private var events: [Double] = []
    private var eventsTruncated = false
    private var overflow = false
    private var sensorFailed = false
    private var accelerationContinuity = CaptureContinuity()
    private var motionContinuity = CaptureContinuity()
    var availability: CaptureAvailability {
        CaptureAvailability(gyroscope: motion.isGyroAvailable,
                            device_motion: motion.isDeviceMotionAvailable,
                            magnetometer: motion.isMagnetometerAvailable)
    }
    func start() {
        motion.gyroUpdateInterval = 1 / 40.0
        motion.deviceMotionUpdateInterval = 1 / 40.0
        motion.magnetometerUpdateInterval = 1 / 40.0
        if motion.isGyroAvailable {
            motion.startGyroUpdates(to: queue) { [weak self] data, error in
                guard let self else { return }
                if let data {
                    self.appendVector(data.timestamp, x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z, gyro: true)
                } else if error != nil { self.fail() }
            }
        }
        if motion.isDeviceMotionAvailable {
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, error in
                guard let self else { return }
                if let data { self.appendMotion(data) } else if error != nil { self.fail() }
            }
        }
        if motion.isMagnetometerAvailable {
            motion.startMagnetometerUpdates(to: queue) { [weak self] data, error in
                guard let self else { return }
                if let data {
                    self.appendVector(data.timestamp, x: data.magneticField.x, y: data.magneticField.y, z: data.magneticField.z, gyro: false)
                } else if error != nil { self.fail() }
            }
        }
    }
    func stop() {
        motion.stopGyroUpdates()
        motion.stopDeviceMotionUpdates()
        motion.stopMagnetometerUpdates()
        queue.waitUntilAllOperationsAreFinished()
    }
    private func fail() {
        lock.lock(); defer { lock.unlock() }
        sensorFailed = true
    }
    func append(_ data: CMAccelerometerData) {
        let received = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        if origin == nil { origin = data.timestamp }
        let t = data.timestamp - origin!
        guard points.last.map({ t > $0.t }) ?? true else { return }
        guard points.count < 19200 else { overflow = true; return }
        accelerationContinuity.observe(timestamp: data.timestamp, received: received)
        points.append(CaptureSample(t: t, received_t: max(0, received - origin!),
                                    x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z))
    }
    private func appendVector(_ timestamp: Double, x: Double, y: Double, z: Double, gyro isGyro: Bool) {
        let received = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        guard let origin, timestamp >= origin else { return }
        let t = timestamp - origin
        let last = isGyro ? gyro.last?.t : magnetometer.last?.t
        guard last.map({ t > $0 }) ?? true else { return }
        guard (isGyro ? gyro.count : magnetometer.count) < 19200 else { overflow = true; return }
        let sample = CaptureSample(t: t, received_t: max(0, received - origin), x: x, y: y, z: z)
        if isGyro { gyro.append(sample) } else { magnetometer.append(sample) }
    }
    private func appendMotion(_ data: CMDeviceMotion) {
        let received = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        guard let origin, data.timestamp >= origin else { return }
        let t = data.timestamp - origin
        guard deviceMotion.last.map({ t > $0.t }) ?? true else { return }
        guard deviceMotion.count < 19200 else { overflow = true; return }
        motionContinuity.observe(timestamp: data.timestamp, received: received)
        let q = data.attitude.quaternion
        deviceMotion.append(CaptureMotion(t: t, received_t: max(0, received - origin),
            gravity: CaptureVector(x: data.gravity.x, y: data.gravity.y, z: data.gravity.z),
            user_acceleration: CaptureVector(x: data.userAcceleration.x, y: data.userAcceleration.y, z: data.userAcceleration.z),
            rotation_rate: CaptureVector(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z),
            attitude: CaptureVector(x: data.attitude.roll, y: data.attitude.pitch, z: data.attitude.yaw),
            quaternion: CaptureQuaternion(x: q.x, y: q.y, z: q.z, w: q.w),
            magnetic_field: CaptureVector(x: data.magneticField.field.x, y: data.magneticField.field.y, z: data.magneticField.field.z),
            magnetic_field_accuracy: Int(data.magneticField.accuracy.rawValue), heading: data.heading))
    }
    var elapsedDuration: Double? {
        lock.lock(); defer { lock.unlock() }
        return origin.map { max(0, ProcessInfo.processInfo.systemUptime - $0) }
    }
    func continuity() -> (gap: Double, delay: Double, age: Double?) {
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        let timestamps = [accelerationContinuity.lastTimestamp,
                          availability.device_motion ? motionContinuity.lastTimestamp : nil].compactMap { $0 }
        return (max(accelerationContinuity.maximumGap, motionContinuity.maximumGap),
                max(accelerationContinuity.maximumDeliveryDelay, motionContinuity.maximumDeliveryDelay),
                timestamps.min().map { max(0, now - $0) })
    }
    func markRep() {
        lock.lock(); defer { lock.unlock() }
        if let t = points.last?.t {
            if events.count < 500 { events.append(t) } else { eventsTruncated = true }
        }
    }
    func snapshot() -> (points: [CaptureSample], gyro: [CaptureSample], motion: [CaptureMotion], magnetic: [CaptureSample], events: [Double], invalid: Bool, eventsTruncated: Bool) {
        lock.lock(); defer { lock.unlock() }
        let available = availability
        let incomplete = (available.gyroscope && gyro.count < 2) || (available.device_motion && deviceMotion.count < 2) || (available.magnetometer && magnetometer.count < 2)
        return (points, gyro, deviceMotion, magnetometer, events, overflow || sensorFailed || incomplete, eventsTruncated)
    }
}

@MainActor
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()
    @Published var recording = false
    @Published var detected = 0
    @Published var draft: CaptureRecord?
    @Published var message = ""
    @Published var pending = 0
    @Published var uploading = false
    private var capture: RawCapture?
    private let detector = MotionDetector()
    private var exercise = "squat"
    private var pace = "normal"
    private var captureNotes = ""
    private var start = Date()
    private var sessionID = UUID()
    var sampleOriginWallTime: Double? { capture?.originWallTime }
    private var timeout: Timer?
    private var continuityTimer: Timer?
    private var continuityWarningShown = false
    private let captureLog = Logger(subsystem: "com.flyingrtx.GymCount.watchkitapp", category: "CaptureContinuity")
    private let storageFolder: URL
    private let send: (URLRequest) async throws -> (Data, URLResponse)
    private func hardwareModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
    private var folder: URL {
        storageFolder
    }
    private func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []
    }
    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DevelopmentCaptures", isDirectory: true),
         send: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        storageFolder = folder
        self.send = send
        pending = files().count
    }
    func begin(_ kind: String, pace: String, notes: String, sessionID: UUID = UUID()) {
        guard !recording && draft == nil else { return }
        guard WatchCaptureLink.shared.isCaptureWorkoutRunning else {
            message = "训练会话未启动，请重试"
            return
        }
        WKInterfaceDevice.current().play(.click)
        continuityWarningShown = false
        let raw = RawCapture(); capture = raw; exercise = kind; self.pace = pace; captureNotes = String(notes.prefix(1000)); start = Date(); detected = 0; message = ""
        self.sessionID = sessionID
        let hasWatchCounter = ["squat", "bench_press", "deadlift"].contains(kind)
        detector.configureForExercise(kind == "squat" ? .squat : kind == "deadlift" ? .deadlift : .benchPress)
        detector.onRawAcceleration = { raw.append($0) }
        detector.onRawRepDetected = { if hasWatchCounter { raw.markRep() } }
        detector.onRepDetected = { [weak self] in
            Task { @MainActor in self?.detected = hasWatchCounter ? (self?.detector.repCount ?? 0) : 0 }
        }
        raw.start()
        detector.startDetection(countRepetitions: hasWatchCounter); recording = detector.isDetecting
        if !recording { raw.stop(); capture = nil; message = "加速度计不可用"; WKInterfaceDevice.current().play(.failure); return }
        // Both entry points have already started an active HealthKit workout.
        continuityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkContinuity() }
        }
        timeout = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }
    private func checkContinuity() {
        guard recording, !continuityWarningShown, let state = capture?.continuity() else { return }
        let age = state.age ?? Date().timeIntervalSince(start)
        guard state.gap > 0.25 || age > 1 else { return }
        continuityWarningShown = true
        message = "采样中断，请结束后重新采集"
        WKInterfaceDevice.current().play(.failure)
        captureLog.error("Capture continuity warning: gap=\(state.gap), age=\(age), delay=\(state.delay)")
    }
    func noteScenePhase(_ phase: ScenePhase) {
        guard recording else { return }
        captureLog.info("Capture scene phase: \(String(describing: phase), privacy: .public)")
        if phase == .active { checkContinuity() }
    }
    func finish(interruption: String? = nil) {
        guard recording else { return }
        WKInterfaceDevice.current().play(.click)
        WatchCaptureLink.shared.noteSampleOrigin(sampleOriginWallTime)
        defer { WatchCaptureLink.shared.captureFinished() }
        detector.stopDetection(); capture?.stop(); timeout?.invalidate(); timeout = nil
        continuityTimer?.invalidate(); continuityTimer = nil; recording = false
        guard let raw = capture else { return }
        let result = raw.snapshot()
        let continuity = raw.continuity()
        captureLog.info("Capture finished: gap=\(continuity.gap), delay=\(continuity.delay)")
        let incomplete = continuity.gap > 0.25 || (continuity.age ?? 0) > 1 || interruption != nil
        if incomplete {
            let diagnostic = "采集诊断：\(interruption ?? "采样中断")，最大缺口 \(String(format: "%.3f", continuity.gap)) 秒，最大回调延迟 \(String(format: "%.3f", continuity.delay)) 秒"
            captureNotes = String(captureNotes.prefix(800)) + "\n" + diagnostic
            message = "采样中断，数据已保留"
        }
        let points = result.points, events = result.events
        guard points.count >= 2, !result.invalid, events.count <= 500 else {
            message = "记录不完整或超出采集上限，请重新采集"; WKInterfaceDevice.current().play(.failure); return
        }
        let saved = UserDefaults.standard.string(forKey: "captureParticipantID").flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(saved.uuidString, forKey: "captureParticipantID")
        let info = Bundle.main.infoDictionary ?? [:]
        draft = CaptureRecord(session_id: sessionID, started_at: start, exercise: exercise, actual_count: 0,
            detected_count: events.count, duration_seconds: [raw.elapsedDuration ?? 0, points.last!.t, result.gyro.last?.t ?? 0, result.motion.last?.t ?? 0, result.magnetic.last?.t ?? 0].max()!, wrist: WKInterfaceDevice.current().wristLocation == .left ? "left" : "right",
            watch_crown: WKInterfaceDevice.current().crownOrientation == .left ? "left" : "right", pace: pace,
            watch_model: hardwareModel(), os_version: WKInterfaceDevice.current().systemVersion,
            app_version: "\(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))",
            algorithm_version: ["squat", "bench_press", "deadlift"].contains(exercise) ? "rules-20261007" : "capture-only-20261009",
            participant_id: saved, notes: captureNotes, samples: points, gyroscope_samples: result.gyro,
            motion_samples: result.motion, magnetometer_samples: result.magnetic, sensor_availability: raw.availability, detected_events: events, reference_events_truncated: result.eventsTruncated)
        detected = events.count; capture = nil
    }
    func persist(_ actual: Int) async {
        guard var record = draft, !uploading else { return }
        message = ""
        record.actual_count = ["rest", "walking", "other"].contains(record.exercise) ? 0 : actual
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var directory = folder; try directory.setResourceValues(values)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let encoded = try encoder.encode(record)
            guard encoded.count <= 16 * 1024 * 1024 else { message = "记录过大，请缩短单组采集"; return }
            try encoded.write(to: folder.appendingPathComponent(record.session_id.uuidString + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            draft = nil; pending = files().count
            await retry()
            // Failed uploads remain editable; success removes the queued file.
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(record.session_id.uuidString + ".json").path) {
                draft = record
            }
        } catch { message = "无法保存到手表，请保留本页并重试"; WKInterfaceDevice.current().play(.failure) }
    }
    func retry() async {
        guard !uploading else { return }
        let queued = files()
        guard !queued.isEmpty else { message = "没有待上传记录"; return }
        message = "正在上传…"
        WKInterfaceDevice.current().play(.click)
        uploading = true; defer { uploading = false; pending = files().count }
        do {
            for file in queued {
                var req = URLRequest(url: URL(string: "https://api.flyingrtx.com/api/v1/gymcount/sessions")!)
                req.httpMethod = "POST"; req.timeoutInterval = 45
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try Data(contentsOf: file)
                let (_, response) = try await send(req)
                guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                    WKInterfaceDevice.current().play(.failure)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    message = status == 409 ? "记录已上传，请在网站修改次数" : status == 429 ? "请稍后重试，数据已保留" : "上传失败（\(status)），数据已保留"
                    return
                }
                try FileManager.default.removeItem(at: file)
            }
            message = "上传完成"
            WKInterfaceDevice.current().play(.success)
        } catch { message = "上传失败，数据已保留，请重试"; WKInterfaceDevice.current().play(.failure) }
    }
    func discard() {
        if let record = draft {
            let file = folder.appendingPathComponent(record.session_id.uuidString + ".json")
            if FileManager.default.fileExists(atPath: file.path) {
                do { try FileManager.default.removeItem(at: file) }
                catch { message = "无法丢弃本地记录，请重试"; return }
            }
        }
        draft = nil; pending = files().count; message = ""
    }
}

struct CollectionView: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = CollectionStore.shared
    @ObservedObject private var link = WatchCaptureLink.shared
    @State private var exercise = "squat"
    @State private var actual = 0
    @State private var notes = ""
    @State private var confirmingUpload = false
    @State private var confirmingRetry = false
    @State private var confirmingDiscard = false

    var body: some View {
        CollectionPanel(
            exercise: $exercise, actual: $actual, notes: $notes,
            recording: store.recording, reviewing: store.draft != nil,
            detected: store.detected, uploading: store.uploading,
            pending: store.pending, message: store.message,
            onStartStop: {
                if store.recording { store.finish() } else {
                    Task { await link.startStandaloneCapture(exercise: exercise, notes: notes) }
                }
            },
            onUpload: { confirmingUpload = true },
            onDiscard: { confirmingDiscard = true },
            onRetry: { confirmingRetry = true },
            onBack: { if let onClose { onClose() } else { dismiss() } },
            onPhoneSync: { Task { await link.startFromWatch(exercise: exercise) } },
            phoneConnecting: link.requestingPhone,
            startingCapture: link.startingCapture,
            authorizing: link.authorizing,
            needsAuthorization: link.needsAuthorization
        )
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
        .tint(GymStyle.mint)
        .alert("同步权限", isPresented: $link.showingAuthorizationHelp) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(link.authorizationMessage + (link.authorizationMessage == "手表尚未获得体能训练权限" ? "。\n\n" + WatchHealthPermissionGuide.message : ""))
        }
        .confirmationDialog("实际 \(actual) 次，确认上传？", isPresented: $confirmingUpload, titleVisibility: .visible) {
            Button("上传 \(actual) 次") {
                let confirmed = actual
                Task { await store.persist(confirmed) }
            }
            Button("继续修改", role: .cancel) {}
        }
        .confirmationDialog("上传保留的 \(store.pending) 组记录？", isPresented: $confirmingRetry, titleVisibility: .visible) {
            Button("重试上传") { Task { await store.retry() } }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("丢弃本组采集？", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("确认丢弃", role: .destructive) { store.discard() }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: store.draft?.session_id) { _, id in
            if id != nil { actual = store.draft?.actual_count ?? 0 }
        }
        .onAppear {
            link.refreshAuthorization()
            if let draft = store.draft { actual = draft.actual_count; exercise = draft.exercise }
            else { exercise = link.requestedExercise }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await link.requestInitialCaptureAuthorization()
            // Phone settings can change while this page stays in the foreground.
            while scenePhase == .active && !Task.isCancelled {
                link.refreshAuthorization()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .onChange(of: link.requestedExercise) { _, value in
            if store.draft == nil { exercise = value }
        }
        .onChange(of: scenePhase) { _, phase in
            store.noteScenePhase(phase)
            if phase == .active { link.refreshAuthorization() }
        }
        .onDisappear {
            link.cancelStandaloneStart()
            if !link.remoteSession { store.finish() }
        }
    }
}

// Shared by the live screen and layout previews; previews never start sensors or upload.
struct CollectionPanel: View {
    @Binding var exercise: String
    @Binding var actual: Int
    @Binding var notes: String
    let recording: Bool
    let reviewing: Bool
    let detected: Int
    let uploading: Bool
    let pending: Int
    let message: String
    let onStartStop: () -> Void
    let onUpload: () -> Void
    let onDiscard: () -> Void
    let onRetry: () -> Void
    var onBack: (() -> Void)? = nil
    var onPhoneSync: (() -> Void)? = nil
    var phoneConnecting = false
    var phoneMessage = ""
    var startingCapture = false
    var authorizing = false
    var needsAuthorization = false
    @State private var choosingExercise = false
    @State private var editingNotes = false

    private var exerciseName: String {
        switch exercise {
        case "bench_press": return "卧推"
        case "deadlift": return "硬拉"
        case "bicep_curl": return "弯举"
        case "rest": return "静止"
        case "walking": return "走动"
        case "other": return "其他非训练"
        default: return "深蹲"
        }
    }

    var body: some View {
        VStack(spacing: GymStyle.spacing) {
            GymHeader(title: reviewing ? "确认采集" : recording ? exerciseName : "采集",
                      back: recording || reviewing || startingCapture ? nil : onBack)
                .padding(.horizontal, GymStyle.inset)
                .padding(.top, 12)
            ScrollView {
            VStack(spacing: GymStyle.spacing) {
                if reviewing {
                    reviewCard
                } else {
                    if !recording {
                    Button { choosingExercise = true } label: {
                        HStack(spacing: 8) {
                            Image("Exercise-\(exercise)")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .accessibilityHidden(true)
                            Text(exerciseName).font(GymStyle.section)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(GymStyle.detail)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(recording || uploading)
                    .accessibilityIdentifier("capture.exercise")
                    }

                    if !recording {
                        Button { editingNotes = true } label: {
                            HStack(spacing: 4) {
                                Text("备注").foregroundStyle(GymStyle.muted)
                                Spacer(minLength: 0)
                                Text(notes.isEmpty ? "选填" : notes)
                                    .lineLimit(1).truncationMode(.tail)
                                    .foregroundStyle(GymStyle.muted)
                                Image(systemName: "chevron.right").font(GymStyle.detail)
                            }
                            .padding(.horizontal, 8)
                            .frame(minHeight: 44)
                            .background(GymStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(uploading)
                        .accessibilityIdentifier("capture.notes")
                    }
                    if recording {
                    VStack(spacing: 2) {
                        Text("手表计数")
                            .font(GymStyle.detail)
                            .foregroundStyle(GymStyle.mint)
                        Text("\(detected)")
                            .font(GymStyle.counter)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    }

                    actionButton(recording ? "结束采集" : startingCapture ? "正在准备采集…" : "开始采集",
                                 primary: !recording, action: onStartStop)
                        .disabled(uploading || (!recording && (startingCapture || authorizing || phoneConnecting)))
                        .accessibilityIdentifier("capture.startStop")
                    if !recording, let onPhoneSync {
                        Button(authorizing ? "等待授权…" : phoneConnecting ? "正在连接…" : needsAuthorization ? "检查同步权限" : "手机同步录像", action: onPhoneSync)
                            .buttonStyle(GymActionStyle())
                            .disabled(phoneConnecting || startingCapture || authorizing || uploading)
                            .accessibilityIdentifier("capture.phoneSync")
                        if !phoneMessage.isEmpty {
                            Text(phoneMessage).font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if reviewing {
                    actionButton(uploading ? "正在上传" : "确认并上传",
                                 primary: true, action: onUpload)
                        .disabled(uploading)
                        .accessibilityIdentifier("capture.upload")
                    Button("丢弃此组", role: .destructive, action: onDiscard)
                        .buttonStyle(GymActionStyle())
                        .disabled(uploading)
                }

                if pending > 0 {
                    actionButton(uploading ? "正在上传" : "重试上传 · \(pending) 组",
                                 primary: false, action: onRetry)
                        .disabled(uploading || recording || reviewing)
                }
                if !message.isEmpty, !(uploading && message == "正在上传…"), message != phoneMessage {
                    Text(message)
                        .font(GymStyle.detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("capture.message")
                }

            }
            .padding(.horizontal, GymStyle.inset)
            .padding(.bottom, 12)
            }
        }
        .gymPage()
        .sheet(isPresented: $editingNotes) {
            ScrollView {
                VStack(spacing: 8) {
                    GymHeader(title: "备注", back: { editingNotes = false })
                    TextField("握持方式、负重等", text: $notes).font(GymStyle.body)
                    Button("完成") { editingNotes = false }
                        .buttonStyle(GymActionStyle(primary: true))
                }
                .gymPageContent()
            }
            .gymPage()
            .tint(GymStyle.mint)
        }
        .sheet(isPresented: $choosingExercise) {
            NavigationStack {
                ScrollView {
                VStack(spacing: GymStyle.spacing) {
                    GymHeader(title: "选择动作", back: { choosingExercise = false })
                    exerciseOption("深蹲", value: "squat")
                    exerciseOption("卧推", value: "bench_press")
                    exerciseOption("硬拉", value: "deadlift")
                    exerciseOption("弯举", value: "bicep_curl")
                    exerciseOption("静止", value: "rest")
                    exerciseOption("走动", value: "walking")
                    exerciseOption("其他非训练", value: "other")
                }
                .gymPageContent(fullWidthHeader: true)
                }
                .gymPage()
                .toolbar(.hidden)
                .tint(GymStyle.mint)
            }
        }
    }

    private var reviewCard: some View {
        VStack(spacing: GymStyle.spacing) {
            HStack {
                Text("已识别")
                Spacer()
                Text("\(detected) 次").foregroundStyle(.white)
            }
                .font(GymStyle.detail)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(GymStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            if ["rest", "walking", "other"].contains(exercise) {
                Text("实际次数：0").font(GymStyle.body)
            } else {
            Text("实际次数")
                .font(GymStyle.detail)
                .foregroundStyle(GymStyle.muted)
            HStack(spacing: 6) {
                countButton("minus", label: "减少实际次数", disabled: uploading || actual == 0) { actual -= 1 }
                VStack(spacing: 2) {
                    Text("\(actual)")
                        .font(GymStyle.counter)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
                countButton("plus", label: "增加实际次数", disabled: uploading || actual == 500) { actual += 1 }
            }
            }
        }
    }

    private func countButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(GymStyle.body)
                .frame(width: 44, height: 44)
                .background(GymStyle.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled || uploading)
        .accessibilityLabel(label)
    }

    private func actionButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(GymActionStyle(primary: primary))
    }

    private func exerciseOption(_ name: String, value: String) -> some View {
        Button {
            exercise = value
            choosingExercise = false
        } label: {
            HStack(spacing: 8) {
                Image("Exercise-\(value)")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text(name)
                Spacer()
                if exercise == value { Image(systemName: "checkmark").foregroundStyle(GymStyle.mint) }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .background(GymStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
#endif
