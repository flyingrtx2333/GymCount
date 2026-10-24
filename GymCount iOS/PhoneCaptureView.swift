import SwiftUI
import AVKit

struct PhoneCaptureView: View {
    @EnvironmentObject var capture: PhoneCaptureStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var exercise = "squat"
    var body: some View {
        ScrollView {
            VStack(spacing: Studio.spacing) {
                CameraPreview(session: capture.camera)
                    .frame(height: 360)
                    .background(Studio.surface)
                    .overlay {
                        if !capture.cameraReady {
                            VStack(spacing: 12) {
                                Image(systemName: "video").font(.system(size: 32, weight: .light))
                                Text(String(localized: "相机预览")).font(.subheadline)
                            }.foregroundStyle(Studio.muted)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Studio.line, lineWidth: 0.5))
                Picker(String(localized: "动作"), selection: $exercise) {
                    Label(String(localized: "杠铃深蹲"), image: "Exercise-squat").tag("squat")
                    Label(String(localized: "卧推"), image: "Exercise-bench_press").tag("bench_press")
                    Label(String(localized: "硬拉"), image: "Exercise-deadlift").tag("deadlift")
                    Label(String(localized: "弯举"), image: "Exercise-bicep_curl").tag("bicep_curl")
                    Label(String(localized: "非训练动作"), image: "Exercise-other").tag("other")
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 52)
                .background(Studio.surface, in: RoundedRectangle(cornerRadius: 16))
                .disabled(capture.recording || capture.busy)
                if capture.recording {
                    Text("\(capture.count)").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                    if exercise == "bench_press" {
                        Text(String(localized: "手表估计 · 前两次一起确认，结束时核准")).font(.caption).foregroundStyle(Studio.muted)
                    }
                }
                if !capture.message.isEmpty, capture.message != String(localized: "正在准备采集…"), capture.message != String(localized: "采集中") {
                    Text(capture.message).font(.callout)
                }
                Button(capture.recording ? String(localized: "结束采集") : capture.busy ? String(localized: "正在准备采集…") : String(localized: "开始采集")) {
                    Task { if capture.recording { await capture.stop() } else { await capture.start(exercise: exercise) } }
                }
                .buttonStyle(StudioPrimaryButton())
                .disabled(capture.busy || !capture.cameraReady)
                if capture.starting {
                    Button(String(localized: "取消启动")) { Task { await capture.cancelStart() } }
                        .buttonStyle(StudioSecondaryButton())
                }
                NavigationLink(String(localized: "采集记录")) { VideoCaptureHistoryView() }
                    .buttonStyle(StudioSecondaryButton())
            }.padding(Studio.inset)
        }
        .navigationTitle(String(localized: "同步采集"))
        .navigationBarTitleDisplayMode(.inline)
        .background(Studio.background)
        .toolbarBackground(Studio.background, for: .navigationBar)
        .tint(Studio.accent)
        .navigationDestination(item: $capture.completedCaptureID) { id in
            VideoCaptureDetailView(id: id)
        }
        .task { await capture.enterCaptureScreen() }
        .onDisappear { capture.leaveCaptureScreen() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await capture.stop(reason: String(localized: "进入后台，采集已结束")) } }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview(); view.previewLayer.session = session; view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        return view
    }
    func updateUIView(_ uiView: Preview, context: Context) {}
}

struct VideoCaptureHistoryView: View {
    @EnvironmentObject var capture: PhoneCaptureStore
    @State private var deletionCandidate: VideoCaptureManifest?
    @State private var confirmingDeletion = false
    @State private var deletionError: String?
    var body: some View {
        List(capture.history) { item in
            NavigationLink { VideoCaptureDetailView(id: item.id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.createdAt.formatted(.dateTime.month().day().hour().minute()))
                        Spacer(minLength: 8)
                        Text(item.uploadStatusTitle)
                            .font(.caption)
                            .foregroundStyle(item.cloudUploadComplete ? Studio.accent : Studio.muted)
                    }
                    HStack(spacing: 8) {
                        if let exercise = ExerciseType(rawValue: item.exercise) { RecordExerciseIcon(exercise: exercise, size: 22) }
                        Text(item.exerciseTitle)
                    }.font(.subheadline.weight(.medium))
                    HStack(alignment: .firstTextBaseline) {
                        if let actual = item.actualCount {
                            Text(String(localized: "实际 \(actual) 次"))
                        } else {
                            Text(String(localized: "手表 \(item.detectedCount) 次 · 待核对"))
                        }
                        Spacer(minLength: 8)
                        if let duration = item.videoDuration, duration.isFinite, duration >= 0 {
                            Text(String(localized: "录像 \(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))"))
                        } else {
                            Text(String(localized: "时长未记录"))
                        }
                    }
                    .font(.caption).monospacedDigit().foregroundStyle(Studio.muted)
                    Text("\(item.videoComplete ? String(localized: "录像已保存") : String(localized: "录像未完成")) · \(item.sensorComplete ? String(localized: "采样已接收") : String(localized: "等待采样"))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = item.error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    deletionCandidate = item
                    confirmingDeletion = true
                } label: {
                    Label(String(localized: "删除"), systemImage: "trash")
                }
                .tint(.red)
                .disabled(!capture.canDeleteCapture(item.id))
            }
            .listRowBackground(Studio.surface)
            .listRowSeparatorTint(Studio.line)
        }
        .scrollContentBackground(.hidden)
        .background(Studio.background)
        .overlay {
            if capture.history.isEmpty {
                ContentUnavailableView(String(localized: "还没有采集记录"), systemImage: "video")
            }
        }
        .navigationTitle(String(localized: "采集记录"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Studio.background, for: .navigationBar)
        .alert(String(localized: "删除这条采集记录？"), isPresented: $confirmingDeletion, presenting: deletionCandidate) { item in
            Button(String(localized: "删除"), role: .destructive) {
                do { try capture.deleteCapture(item.id) }
                catch { deletionError = error.localizedDescription }
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: { item in
            Text(item.exerciseTitle + " · " + item.createdAt.formatted(.dateTime.month().day().hour().minute()) + "\n\n" + String(localized: "将删除此手机上的录像、采样和标注。已上传的云端记录会保留。"))
        }
        .alert(String(localized: "无法删除采集记录"), isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button(String(localized: "确定"), role: .cancel) {}
        } message: {
            Text(deletionError ?? "")
        }
    }
}

struct VideoCaptureDetailView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject var capture: PhoneCaptureStore
    let id: UUID
    @State private var player: AVPlayer?
    @State private var actual = 0
    @State private var sharing = false
    @State private var confirmingUpload = false
    var body: some View {
        ScrollView {
            if let item = capture.history.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(item.exerciseTitle).font(.headline)
                        Spacer()
                        Text(item.uploadStatusTitle)
                            .font(.caption)
                            .foregroundStyle(item.cloudUploadComplete ? Studio.accent : Studio.muted)
                    }
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 300)
                            .background(Studio.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Stepper(String(localized: "实际次数：\(actual) 次"), value: $actual, in: 0...500)
                            .font(.headline)
                            .disabled(capture.uploading)
                            .onChange(of: actual) { _, value in capture.setActual(value, for: id) }
                        HStack {
                            Text(String(localized: "手表计数：\(item.detectedCount) 次"))
                            Spacer(minLength: 8)
                            Text(String(localized: "已标记 \(item.referenceEvents.count) 次"))
                        }
                        .font(.caption).monospacedDigit().foregroundStyle(Studio.muted)
                        if let review = capture.benchReviews[id] {
                            Text(review.count.map { String(localized: "本机复核：\($0) 次（实验）") } ?? String(localized: "本机复核：数据不足，需人工核对"))
                                .font(.caption).foregroundStyle(Studio.muted)
                        }
                        Divider().overlay(Studio.line)
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                            Button(String(localized: "标记一次")) {
                                if let player {
                                    player.pause()
                                    capture.markReference(id, at: CMTimeGetSeconds(player.currentTime()))
                                    actual = capture.history.first(where: { $0.id == id })?.actualCount ?? actual
                                }
                            }
                            .buttonStyle(.borderedProminent).tint(Studio.accent).foregroundStyle(Studio.onAccent)
                            .disabled(capture.uploading)
                            Button(String(localized: "撤销标记")) {
                                capture.undoReference(id)
                                actual = capture.history.first(where: { $0.id == id })?.actualCount ?? actual
                            }
                            .buttonStyle(.bordered).tint(Studio.accent)
                            .disabled(capture.uploading || item.referenceEvents.isEmpty)
                            Spacer(minLength: 0)
                        }
                        .controlSize(.large)
                    }
                    .padding(16)
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
                    if let offset = item.sensorOffsetInVideo {
                        DisclosureGroup {
                            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                                Button(String(localized: "对齐 −0.1 秒")) { capture.adjustAlignment(id, by: -0.1) }
                                Button(String(localized: "对齐 +0.1 秒")) { capture.adjustAlignment(id, by: 0.1) }
                                Spacer(minLength: 0)
                            }
                            .buttonStyle(.bordered).controlSize(.large)
                            .disabled(capture.uploading)
                            .padding(.top, 12)
                        } label: {
                            HStack {
                                Text(String(localized: "采样对齐"))
                                Spacer()
                                Text(offset.formatted(.number.precision(.fractionLength(2))) + " s")
                                    .monospacedDigit().foregroundStyle(Studio.muted)
                            }
                            .font(.subheadline)
                            .frame(minHeight: 28)
                        }
                        .tint(Studio.accent)
                        .padding(16)
                        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if !item.sensorComplete {
                        Button(String(localized: "重试接收采样")) { Task { await capture.receiveAgain(id) } }
                            .buttonStyle(.bordered).tint(Studio.accent).controlSize(.large)
                    }
                    if let error = item.error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }.padding(Studio.inset)
                .task(id: id) { await capture.reviewBench(id) }
                .onAppear {
                    actual = item.actualCount ?? 0
                    if player == nil { player = AVPlayer(url: capture.videoURL(id)) }
                }
                .sheet(isPresented: $sharing) {
                    FileShareView(files: [capture.videoURL(id), capture.sensorURL(id), capture.folder(id).appendingPathComponent("manifest.json")].filter { FileManager.default.fileExists(atPath: $0.path) })
                }
                .confirmationDialog(String(localized: "实际 \(actual) 次，确认上传？"), isPresented: $confirmingUpload, titleVisibility: .visible) {
                    Button(String(localized: "上传 \(actual) 次")) {
                        capture.setActual(actual, for: id)
                        Task { await capture.upload(id) }
                    }
                    Button(String(localized: "继续修改"), role: .cancel) {}
                }
            }
        }
        .background(Studio.background)
        .navigationTitle(String(localized: "录像核对"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Studio.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sharing = true } label: {
                    Label(String(localized: "分享文件"), systemImage: "square.and.arrow.up")
                }
                .disabled(!(capture.history.first(where: { $0.id == id })?.videoComplete ?? false))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let item = capture.history.first(where: { $0.id == id }) {
                Button(capture.uploading ? String(localized: "正在上传…") : String(localized: "上传录像与采样")) {
                    player?.pause()
                    confirmingUpload = true
                }
                .buttonStyle(StudioPrimaryButton())
                .frame(maxWidth: .infinity)
                .disabled(capture.uploading || !item.sensorComplete || item.actualCount == nil)
                .padding(.horizontal, Studio.inset).padding(.vertical, 12)
                .background(Studio.background)
                .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 0.5) }
            }
        }
        .sheet(isPresented: Binding(
            get: { capture.uploadStatus?.id == id },
            set: { if !$0 { capture.dismissUploadStatus(id) } }
        )) {
            CaptureUploadProgressView(id: id)
                .environmentObject(capture)
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled(capture.uploading)
        }
        .onDisappear { player?.pause() }
    }
}

private struct CaptureUploadProgressView: View {
    @EnvironmentObject var capture: PhoneCaptureStore
    let id: UUID
    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            if let status = capture.uploadStatus, status.id == id {
                Image(systemName: status.stage == .succeeded ? "checkmark.circle.fill" : status.stage == .failed ? "exclamationmark.triangle.fill" : "arrow.up.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(status.stage == .failed ? Color.orange : Studio.accent)
                    .accessibilityHidden(true)
                Text(status.stage.title).font(.title3.weight(.semibold))
                if status.finished {
                    Text(status.detail).font(.callout).foregroundStyle(Studio.muted)
                    if status.stage == .failed {
                        Button(String(localized: "重试上传")) { Task { await capture.upload(id) } }
                            .buttonStyle(StudioPrimaryButton())
                    }
                    Button(String(localized: "完成")) { capture.dismissUploadStatus(id) }
                        .buttonStyle(StudioSecondaryButton())
                } else {
                    ProgressView(value: status.progress)
                        .progressViewStyle(.linear)
                        .tint(Studio.accent)
                        .accessibilityLabel(Text(status.stage.title))
                    if let progress = status.progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.headline.monospacedDigit())
                    }
                    Text(String(localized: "上传期间请保持应用打开"))
                        .font(.footnote).foregroundStyle(Studio.muted)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(Studio.inset * 2)
        .frame(maxWidth: .infinity)
        }
        .background(Studio.background)
    }
}

private struct FileShareView: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: files, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
