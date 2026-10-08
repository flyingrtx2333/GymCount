#if DEBUG || GYMCOUNT_CAPTURE
import SwiftUI
import CoreMotion
import WatchKit
import Darwin

private struct CaptureSample: Codable {
    let t: Double
    let x: Double
    let y: Double
    let z: Double
}

private struct CaptureRecord: Codable {
    let schema_version = 1
    let session_id: UUID
    let started_at: Date
    let exercise: String
    var actual_count: Int
    let detected_count: Int
    let duration_seconds: Double
    let sample_rate_hz = 40.0
    let acceleration_unit = "g"
    let wrist: String
    let watch_model: String
    let os_version: String
    let app_version: String
    let algorithm_version = "rules-20261007"
    let participant_id: UUID
    let notes = "development-foreground-capture"
    let samples: [CaptureSample]
    let detected_events: [Double]
}

// Called directly on the serial motion queue; the UI's chart callback is never used.
private final class RawCapture {
    private let lock = NSLock()
    private var origin: Double?
    private var points: [CaptureSample] = []
    private var events: [Double] = []
    private(set) var overflow = false
    func append(_ data: CMAccelerometerData) {
        lock.lock(); defer { lock.unlock() }
        if points.count >= 19200 { overflow = true; return }
        if origin == nil { origin = data.timestamp }
        let t = data.timestamp - origin!
        guard points.last.map({ t > $0.t }) ?? true else { return }
        points.append(CaptureSample(t: t, x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z))
    }
    func markRep() {
        lock.lock(); defer { lock.unlock() }
        if let t = points.last?.t { events.append(t) }
    }
    func snapshot() -> ([CaptureSample], [Double], Bool) {
        lock.lock(); defer { lock.unlock() }; return (points, events, overflow)
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
    func begin(_ kind: String) {
        guard !recording && draft == nil else { return }
        let raw = RawCapture(); capture = raw; exercise = kind; start = Date(); detected = 0; message = ""
        detector.configureForExercise(kind == "squat" ? .squat : kind == "deadlift" ? .deadlift : .benchPress)
        detector.onRawAcceleration = { raw.append($0) }
        detector.onRawRepDetected = { raw.markRep() }
        detector.onRepDetected = { [weak self] in
            Task { @MainActor in self?.detected = self?.detector.repCount ?? 0 }
        }
        detector.startDetection(); recording = detector.isDetecting
        if !recording { message = "加速度计不可用"; return }
        // A bounded, foreground test session; not a HealthKit workout.
        timeout = Timer.scheduledTimer(withTimeInterval: 470, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }
    func finish() {
        guard recording else { return }
        detector.stopDetection(); timeout?.invalidate(); timeout = nil; recording = false
        guard let (points, events, overflow) = capture?.snapshot(), points.count >= 2, !overflow, events.count <= 500 else {
            message = "记录不完整或超出采集上限，请重新采集"; return
        }
        let saved = UserDefaults.standard.string(forKey: "captureParticipantID").flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(saved.uuidString, forKey: "captureParticipantID")
        let info = Bundle.main.infoDictionary ?? [:]
        draft = CaptureRecord(session_id: UUID(), started_at: start, exercise: exercise, actual_count: 0,
            detected_count: events.count, duration_seconds: points.last!.t, wrist: WKInterfaceDevice.current().wristLocation == .left ? "left" : "right",
            watch_model: hardwareModel(), os_version: WKInterfaceDevice.current().systemVersion,
            app_version: "\(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))",
            participant_id: saved, samples: points, detected_events: events)
        detected = events.count; capture = nil
    }
    func persist(_ actual: Int) async {
        guard var record = draft, !uploading else { return }
        record.actual_count = actual
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var directory = folder; try directory.setResourceValues(values)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: folder.appendingPathComponent(record.session_id.uuidString + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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

    var body: some View {
        CollectionPanel(
            exercise: $exercise, actual: $actual,
            recording: store.recording, reviewing: store.draft != nil,
            detected: store.detected, uploading: store.uploading,
            pending: store.pending, message: store.message,
            onStartStop: {
                if store.recording { store.finish() } else { store.begin(exercise) }
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

    private var exerciseName: String {
        switch exercise {
        case "bench_press": return "卧推"
        case "deadlift": return "硬拉"
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
                }
                .font(GymStyle.body)
                .navigationTitle("选择动作")
            }
        }
    }

    private var reviewCard: some View {
        VStack(spacing: 8) {
            Text("\(exerciseName) · 识别 \(detected) 次")
                .font(GymStyle.detail)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
