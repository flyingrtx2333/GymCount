#if DEBUG || GYMCOUNT_CAPTURE
import SwiftUI
import CoreMotion
import WatchKit
import Darwin

private struct CaptureSample: Encodable {
    let t: Double
    let received_t: Double
    let x: Double
    let y: Double
    let z: Double
}

private struct CaptureVector: Encodable {
    let x: Double
    let y: Double
    let z: Double
}

private struct CaptureQuaternion: Encodable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

private struct CaptureMotion: Encodable {
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

private struct CaptureAvailability: Encodable {
    let gyroscope: Bool
    let device_motion: Bool
    let magnetometer: Bool
}

private struct CaptureRecord: Encodable {
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
    let algorithm_version = "rules-20261007"
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
    private var points: [CaptureSample] = []
    private var gyro: [CaptureSample] = []
    private var deviceMotion: [CaptureMotion] = []
    private var magnetometer: [CaptureSample] = []
    private var events: [Double] = []
    private var eventsTruncated = false
    private var overflow = false
    private var sensorFailed = false
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
private final class CollectionStore: ObservableObject {
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
    private var timeout: Timer?
    private func hardwareModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DevelopmentCaptures", isDirectory: true)
    }
    private func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []
    }
    init() { pending = files().count }
    func begin(_ kind: String, pace: String, notes: String) {
        guard !recording && draft == nil else { return }
        let raw = RawCapture(); capture = raw; exercise = kind; self.pace = pace; captureNotes = String(notes.prefix(1000)); start = Date(); detected = 0; message = ""
        let isTraining = ["squat", "bench_press", "deadlift"].contains(kind)
        detector.configureForExercise(kind == "squat" ? .squat : kind == "deadlift" ? .deadlift : .benchPress)
        detector.onRawAcceleration = { raw.append($0) }
        detector.onRawRepDetected = { if isTraining { raw.markRep() } }
        detector.onRepDetected = { [weak self] in
            Task { @MainActor in self?.detected = isTraining ? (self?.detector.repCount ?? 0) : 0 }
        }
        raw.start()
        detector.startDetection(); recording = detector.isDetecting
        if !recording { raw.stop(); capture = nil; message = "加速度计不可用"; return }
        // A bounded, foreground test session; not a HealthKit workout.
        timeout = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }
    func finish() {
        guard recording else { return }
        detector.stopDetection(); capture?.stop(); timeout?.invalidate(); timeout = nil; recording = false
        guard let raw = capture else { return }
        let result = raw.snapshot()
        let points = result.points, events = result.events
        guard points.count >= 2, !result.invalid, events.count <= 500 else {
            message = "记录不完整或超出采集上限，请重新采集"; return
        }
        let saved = UserDefaults.standard.string(forKey: "captureParticipantID").flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(saved.uuidString, forKey: "captureParticipantID")
        let info = Bundle.main.infoDictionary ?? [:]
        draft = CaptureRecord(session_id: UUID(), started_at: start, exercise: exercise, actual_count: 0,
            detected_count: events.count, duration_seconds: [points.last!.t, result.gyro.last?.t ?? 0, result.motion.last?.t ?? 0, result.magnetic.last?.t ?? 0].max()!, wrist: WKInterfaceDevice.current().wristLocation == .left ? "left" : "right",
            watch_crown: WKInterfaceDevice.current().crownOrientation == .left ? "left" : "right", pace: pace,
            watch_model: hardwareModel(), os_version: WKInterfaceDevice.current().systemVersion,
            app_version: "\(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))",
            participant_id: saved, notes: captureNotes, samples: points, gyroscope_samples: result.gyro,
            motion_samples: result.motion, magnetometer_samples: result.magnetic, sensor_availability: raw.availability, detected_events: events, reference_events_truncated: result.eventsTruncated)
        detected = events.count; capture = nil
    }
    func persist(_ actual: Int) async {
        guard var record = draft, !uploading else { return }
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
        } catch { message = "无法保存到手表，请保留本页并重试" }
    }
    func retry() async {
        guard !uploading else { return }
        uploading = true; defer { uploading = false; pending = files().count }
        do {
            for file in files() {
                var req = URLRequest(url: URL(string: "https://api.flyingrtx.com/api/v1/gymcount/sessions")!)
                req.httpMethod = "POST"; req.timeoutInterval = 45
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try Data(contentsOf: file)
                let (_, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                    message = "上传失败（\((response as? HTTPURLResponse)?.statusCode ?? 0)），记录仍在手表"; return
                }
                try FileManager.default.removeItem(at: file)
            }
            message = "上传完成"
        } catch { message = "网络未完成，记录已保留，可安全重试" }
    }
    func discard() { draft = nil; message = "" }
}

struct CollectionView: View {
    @StateObject private var store = CollectionStore()
    @State private var exercise = "squat"
    @State private var actual = 10
    @State private var pace = "normal"
    @State private var notes = ""

    var body: some View {
        CollectionPanel(
            exercise: $exercise, actual: $actual, pace: $pace, notes: $notes,
            recording: store.recording, reviewing: store.draft != nil,
            detected: store.detected, uploading: store.uploading,
            pending: store.pending, message: store.message,
            onStartStop: {
                if store.recording { store.finish() } else { store.begin(exercise, pace: pace, notes: notes) }
            },
            onUpload: { Task { await store.persist(actual) } },
            onDiscard: { store.discard() },
            onRetry: { Task { await store.retry() } }
        )
        .navigationTitle("采集测试")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(store.recording || store.draft != nil)
        .onDisappear { store.finish() }
    }
}

// Shared by the live screen and layout previews; previews never start sensors or upload.
struct CollectionPanel: View {
    @Binding var exercise: String
    @Binding var actual: Int
    @Binding var pace: String
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
    @State private var choosingExercise = false
    @State private var choosingPace = false

    private var paceName: String {
        switch pace {
        case "slow": return "慢速"
        case "fast": return "快速"
        case "mixed": return "混合"
        default: return "正常"
        }
    }

    private var exerciseName: String {
        switch exercise {
        case "bench_press": return "卧推"
        case "deadlift": return "硬拉"
        case "rest": return "静止"
        case "walking": return "走动"
        case "other": return "其他非训练"
        default: return "深蹲"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if reviewing {
                    reviewCard
                } else {
                    Button { choosingExercise = true } label: {
                        HStack {
                            Text(exerciseName)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(GymStyle.detail)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(GymStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(recording || uploading)
                    .accessibilityIdentifier("capture.exercise")

                    if !recording {
                        Button { choosingPace = true } label: {
                            HStack(spacing: 4) {
                                Text("动作速度")
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text(paceName)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(GymStyle.detail)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(GymStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: false, vertical: true)
                        .disabled(uploading)
                        .accessibilityIdentifier("capture.pace")
                        TextField("备注：握持方式、负重等", text: $notes)
                            .disabled(uploading)
                    }
                    VStack(spacing: 2) {
                        Text(recording ? "正在采集" : "已识别次数")
                            .font(GymStyle.detail)
                            .foregroundStyle(recording ? Color.green : Color.secondary)
                        Text("\(detected)")
                            .font(GymStyle.counter)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 0)

                    actionButton(recording ? "结束采集" : "开始采集",
                                 icon: recording ? "stop.fill" : "play.fill",
                                 color: recording ? .orange : .green, action: onStartStop)
                        .disabled(uploading)
                        .accessibilityIdentifier("capture.startStop")
                }

                if reviewing {
                    actionButton(uploading ? "正在上传" : "确认并上传",
                                 icon: "arrow.up.circle.fill", color: .green, action: onUpload)
                        .disabled(uploading)
                        .accessibilityIdentifier("capture.upload")
                    Button("丢弃此组", role: .destructive, action: onDiscard)
                        .font(GymStyle.detail)
                        .buttonStyle(.plain)
                        .frame(minHeight: 36)
                        .disabled(uploading)
                }

                if pending > 0 {
                    actionButton(uploading ? "正在上传" : "重试上传 · \(pending) 组",
                                 icon: "arrow.clockwise", color: .blue, action: onRetry)
                        .disabled(uploading || recording)
                }
                if !message.isEmpty {
                    Text(message)
                        .font(GymStyle.detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("capture.message")
                }

            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .font(GymStyle.body)
        .sheet(isPresented: $choosingExercise) {
            NavigationStack {
                List {
                    exerciseOption("深蹲", value: "squat")
                    exerciseOption("卧推", value: "bench_press")
                    exerciseOption("硬拉", value: "deadlift")
                    exerciseOption("静止", value: "rest")
                    exerciseOption("走动", value: "walking")
                    exerciseOption("其他非训练", value: "other")
                }
                .font(GymStyle.body)
                .navigationTitle("选择动作")
            }
        }
        .sheet(isPresented: $choosingPace) {
            NavigationStack {
                List {
                    paceOption("正常", value: "normal")
                    paceOption("慢速", value: "slow")
                    paceOption("快速", value: "fast")
                    paceOption("混合", value: "mixed")
                }
                .font(GymStyle.body)
                .navigationTitle("动作速度")
            }
        }
    }

    private var reviewCard: some View {
        VStack(spacing: 8) {
            Text("\(exerciseName) · 识别 \(detected) 次")
                .font(GymStyle.detail)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if ["rest", "walking", "other"].contains(exercise) {
                Text("非训练样本 · 实际次数 0").font(GymStyle.body)
            } else {
            HStack(spacing: 6) {
                countButton("minus", label: "减少实际次数", disabled: actual == 0) { actual -= 1 }
                VStack(spacing: 2) {
                    Text("实际次数")
                        .font(GymStyle.detail)
                        .foregroundStyle(.secondary)
                    Text("\(actual)")
                        .font(GymStyle.counter)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
                countButton("plus", label: "增加实际次数", disabled: actual == 500) { actual += 1 }
            }
            }
        }
        .padding(8)
        .background(GymStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func countButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(GymStyle.body)
                .frame(width: 32, height: 40)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(disabled || uploading)
        .accessibilityLabel(label)
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(GymStyle.button)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(color)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func paceOption(_ name: String, value: String) -> some View {
        Button {
            pace = value
            choosingPace = false
        } label: {
            HStack {
                Text(name)
                Spacer()
                if pace == value { Image(systemName: "checkmark").foregroundStyle(.green) }
            }
            .frame(minHeight: 36)
        }
    }

    private func exerciseOption(_ name: String, value: String) -> some View {
        Button {
            exercise = value
            choosingExercise = false
        } label: {
            HStack {
                Text(name)
                Spacer()
                if exercise == value { Image(systemName: "checkmark").foregroundStyle(.green) }
            }
        }
    }
}
#endif
