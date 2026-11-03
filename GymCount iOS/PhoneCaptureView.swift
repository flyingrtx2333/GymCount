#if DEBUG
import SwiftUI
import AVKit

struct PhoneCaptureView: View {
    @EnvironmentObject var capture: PhoneCaptureStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var heightClass
    @State private var exercise = "squat"
    var body: some View {
        ScrollView {
            VStack(spacing: Studio.spacing) {
                CameraPreview(session: capture.camera, device: capture.cameraDevice)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: heightClass == .compact ? 240 : 480)
                    .background(Studio.surface)
                    .overlay {
                        if !capture.cameraReady {
                            VStack(spacing: 12) {
                                Image(systemName: "video").font(.system(size: 32, weight: .light))
                                Text(String(localized: "相机预览")).font(Studio.Fonts.body)
                            }.foregroundStyle(Studio.muted)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Studio.mediaRadius))
                    .overlay(RoundedRectangle(cornerRadius: Studio.mediaRadius).stroke(Studio.line, lineWidth: Studio.hairline))
                    .frame(maxWidth: .infinity)
                Menu {
                    Picker(String(localized: "动作"), selection: $exercise) {
                        ForEach(exerciseOptions, id: \.id) { option in
                            exerciseOption(option.title, icon: "Exercise-" + option.id).tag(option.id)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        let option = exerciseOptions.first { $0.id == exercise }!
                        exerciseOption(option.title, icon: "Exercise-" + option.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down").font(Studio.Fonts.caption)
                    }
                    .padding(.horizontal, Studio.inset).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                    .background(Studio.surface, in: RoundedRectangle(cornerRadius: Studio.mediaRadius))
                }
                .buttonStyle(RecordPressStyle())
                .accessibilityIdentifier("capture-exercise-picker")
                .disabled(capture.recording || capture.busy)
                if capture.recording {
                    Text("\(capture.count)").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                }
                if !capture.message.isEmpty, capture.message != String(localized: "正在准备采集…"), capture.message != String(localized: "采集中") {
                    Text(capture.message).font(Studio.Fonts.body)
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
        .recordCanvasSpacing()
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

    private var exerciseOptions: [(id: String, title: String)] {
        [("squat", String(localized: "杠铃深蹲")), ("bench_press", String(localized: "卧推")),
         ("deadlift", String(localized: "硬拉")), ("bicep_curl", String(localized: "弯举")),
         ("other", String(localized: "非训练动作"))]
    }

    private func exerciseOption(_ title: String, icon: String) -> some View {
        Label { Text(title).font(Studio.Fonts.body).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(icon).resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var rotation: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?

        func useDevice(_ device: AVCaptureDevice?) {
            guard rotation?.device !== device else { return }
            observation = nil
            rotation = device.map { AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: previewLayer) }
            observation = rotation?.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
                // RotationCoordinator delivers these updates on the main queue.
                MainActor.assumeIsolated { self?.updateRotation() }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateRotation()
        }

        private func updateRotation() {
            guard let angle = rotation?.videoRotationAngleForHorizonLevelPreview,
                  let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle),
                  connection.videoRotationAngle != angle else { return }
            connection.videoRotationAngle = angle
        }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview(); view.previewLayer.session = session; view.previewLayer.videoGravity = .resizeAspect
        view.useDevice(device)
        return view
    }
    func updateUIView(_ uiView: Preview, context: Context) { uiView.useDevice(device) }
    static func dismantleUIView(_ uiView: Preview, coordinator: ()) {
        uiView.useDevice(nil)
        uiView.previewLayer.session = nil
    }
}

struct VideoCaptureHistoryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject var capture: PhoneCaptureStore
    @State private var deletionCandidate: VideoCaptureManifest?
    @State private var confirmingDeletion = false
    @State private var deletionError: String?
    var body: some View {
        List(capture.history) { item in
            NavigationLink { VideoCaptureDetailView(id: item.id) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                    layout {
                        HStack(spacing: 8) {
                            if let exercise = ExerciseType(rawValue: item.exercise) { RecordExerciseIcon(exercise: exercise, size: 26) }
                            Text(item.exerciseTitle)
                        }
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        if let actual = item.actualCount {
                            Text(String(localized: "实际 \(actual) 次")).monospacedDigit()
                        } else {
                            Text(String(localized: "手表 \(item.detectedCount) 次 · 待核对")).monospacedDigit()
                        }
                    }.font(Studio.Fonts.body.weight(.medium)).foregroundStyle(Studio.ink)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { captureMetadata(item) }
                        VStack(alignment: .leading, spacing: 4) { captureMetadata(item) }
                    }.font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                    if !item.videoComplete || !item.sensorComplete {
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 10))) {
                            if !item.videoComplete { Label(String(localized: "录像未完成"), systemImage: "exclamationmark.circle") }
                            if !item.sensorComplete { Label(String(localized: "等待采样"), systemImage: "applewatch") }
                        }
                        .font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                    }
                    if let error = item.error { Text(error).font(Studio.Fonts.caption).foregroundStyle(.red) }
                }.padding(.vertical, 10).frame(minHeight: Studio.rowHeight)
            }
            .accessibilityIdentifier("capture-record-\(item.id.uuidString)")
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
            .listRowInsets(EdgeInsets(top: 0, leading: Studio.inset, bottom: 0, trailing: Studio.inset))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Studio.line)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Studio.background)
        .recordCanvasSpacing()
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
    @ViewBuilder private func captureMetadata(_ item: VideoCaptureManifest) -> some View {
        Text(item.createdAt.formatted(Calendar.current.component(.year, from: item.createdAt) == Calendar.current.component(.year, from: Date())
            ? .dateTime.month().day().hour().minute() : .dateTime.year().month().day().hour().minute()))
        if let duration = item.videoDuration, duration.isFinite, duration >= 0 {
            Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
        }
        Text(item.uploadStatusTitle).foregroundStyle(item.cloudUploadComplete ? Studio.accent : Studio.muted)
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
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))) {
                        if let exercise = ExerciseType(rawValue: item.exercise) {
                            RecordExerciseLabel(exercise: exercise, size: 26).font(Studio.Fonts.section)
                        } else { Text(item.exerciseTitle).font(Studio.Fonts.section) }
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        Text(item.uploadStatusTitle)
                            .font(Studio.Fonts.caption)
                            .foregroundStyle(item.cloudUploadComplete ? Studio.accent : Studio.muted)
                    }
                    if let player {
                        VideoPlayer(player: player)
                            .aspectRatio(4.0 / 3.0, contentMode: .fit)
                            .frame(maxWidth: 560)
                            .background(Studio.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Studio.mediaRadius))
                            .frame(maxWidth: .infinity)
                    } else {
                        RecordInlineState(title: String(localized: "录像未完成"), systemImage: "video.slash")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        if isNonTraining(item) {
                            Text(String(localized: "实际次数：\(0) 次")).font(Studio.Fonts.section)
                        } else {
                            Stepper(String(localized: "实际次数：\(actual) 次"), value: $actual, in: 0...500)
                                .font(Studio.Fonts.section)
                                .disabled(capture.uploading)
                                .onChange(of: actual) { _, value in capture.setActual(value, for: id) }
                        }
                        if item.actualCount == nil {
                            Text(String(localized: "待核对")).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                        }
                        if let error = capture.actualCountErrors[id] {
                            Text(error).font(Studio.Fonts.caption).foregroundStyle(.red)
                        }
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))) {
                            Text(String(localized: "手表计数：\(item.detectedCount) 次"))
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            Text(String(localized: "已标记 \(item.referenceEvents.count) 次"))
                        }
                        .font(Studio.Fonts.caption).monospacedDigit().foregroundStyle(Studio.muted)
                        if let review = capture.benchReviews[id] {
                            Text(review.count.map { String(localized: "本机复核：\($0) 次（实验）") } ?? String(localized: "本机复核：数据不足，需人工核对"))
                                .font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                        }
                        Divider().overlay(Studio.line)
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                            Button {
                                if let player {
                                    player.pause()
                                    capture.markReference(id, at: CMTimeGetSeconds(player.currentTime()))
                                    actual = capture.history.first(where: { $0.id == id })?.actualCount ?? actual
                                }
                            } label: {
                                Text(String(localized: "标记一次"))
                            }
                            .buttonStyle(StudioPrimaryButton())
                            .disabled(capture.uploading || player == nil || isNonTraining(item) || item.referenceEvents.count >= 500)
                            .accessibilityIdentifier("capture-reference-mark")
                            Button {
                                capture.undoReference(id)
                                actual = capture.history.first(where: { $0.id == id })?.actualCount ?? actual
                            } label: {
                                Text(String(localized: "撤销标记")).font(Studio.Fonts.body.weight(.medium))
                                    .frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
                            }
                            .buttonStyle(RecordPressStyle())
                            .disabled(capture.uploading || item.referenceEvents.isEmpty)
                            Spacer(minLength: 0)
                        }
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 4)
                    if let offset = item.sensorOffsetInVideo {
                        DisclosureGroup {
                            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                                Button { capture.adjustAlignment(id, by: -0.1) } label: {
                                    Text(String(localized: "对齐 −0.1 秒")).frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
                                }
                                Button { capture.adjustAlignment(id, by: 0.1) } label: {
                                    Text(String(localized: "对齐 +0.1 秒")).frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
                                }
                                Spacer(minLength: 0)
                            }
                            .buttonStyle(RecordPressStyle()).controlSize(.regular)
                            .disabled(capture.uploading)
                            .padding(.top, 4).frame(minHeight: Studio.controlHeight)
                        } label: {
                            HStack {
                                Text(String(localized: "采样对齐"))
                                Spacer()
                                Text(offset.formatted(.number.precision(.fractionLength(2))) + " s")
                                    .monospacedDigit().foregroundStyle(Studio.muted)
                            }
                            .font(Studio.Fonts.body)
                            .frame(minHeight: Studio.controlHeight)
                        }
                        .tint(Studio.accent)
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: Studio.hairline) }
                    }
                    if !item.sensorComplete {
                        Button(capture.sampleReceiveStates[id]?.isReceiving == true ? String(localized: "正在接收采样…") : String(localized: "重试接收采样")) { Task { await capture.receiveAgain(id) } }
                            .buttonStyle(StudioSecondaryButton())
                            .disabled(capture.uploading || capture.sampleReceiveStates[id]?.isReceiving == true)
                    }
                    if let state = capture.sampleReceiveStates[id] {
                        HStack(spacing: 8) {
                            if state.isReceiving { ProgressView() }
                            Text(state.message).font(Studio.Fonts.caption)
                        }
                        .foregroundStyle({ if case .failed = state { Color.red } else { Studio.muted } }())
                    }
                    if let error = item.error {
                        Text(error).font(Studio.Fonts.caption).foregroundStyle(.red)
                    }
                }.padding(Studio.inset)
                .task(id: id) { await capture.reviewBench(id) }
                .onAppear {
                    actual = isNonTraining(item) ? 0 : item.actualCount ?? 0
                }
                .task(id: "\(id)/\(item.videoComplete)") {
                    if player == nil, FileManager.default.fileExists(atPath: capture.videoURL(id).path) {
                        player = AVPlayer(url: capture.videoURL(id))
                    }
                }
                .sheet(isPresented: $sharing) {
                    FileShareView(files: [capture.videoURL(id), capture.sensorURL(id), capture.folder(id).appendingPathComponent("manifest.json")].filter { FileManager.default.fileExists(atPath: $0.path) })
                }
                .confirmationDialog(String(localized: "实际 \(actual) 次，确认上传？"), isPresented: $confirmingUpload, titleVisibility: .visible) {
                    Button(String(localized: "上传 \(actual) 次")) {
                        guard capture.setActual(actual, for: id) else { return }
                        Task { await capture.upload(id) }
                    }
                    Button(String(localized: "继续修改"), role: .cancel) {}
                }
            } else {
                ContentUnavailableView(String(localized: "记录不存在"), systemImage: "video")
                    .frame(maxWidth: .infinity)
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
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(capture.uploading || !item.sensorComplete || !item.videoComplete || player == nil)
                .accessibilityIdentifier("capture-upload")
                .padding(.horizontal, Studio.inset).padding(.vertical, 12)
                .background(Studio.background)
                .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: Studio.hairline) }
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
        .recordCanvasSpacing()
    }

    private func isNonTraining(_ item: VideoCaptureManifest) -> Bool {
        ["rest", "walking", "other"].contains(item.exercise)
    }
}

private struct CaptureUploadProgressView: View {
    @EnvironmentObject var capture: PhoneCaptureStore
    let id: UUID
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Studio.spacing) {
            if let status = capture.uploadStatus, status.id == id {
                HStack(spacing: 10) {
                    Image(systemName: status.stage == .succeeded ? "checkmark.circle.fill" : status.stage == .failed ? "exclamationmark.triangle.fill" : "arrow.up.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(status.stage == .failed ? Color.orange : Studio.accent)
                        .accessibilityHidden(true)
                    Text(status.stage.title).font(Studio.Fonts.modalTitle)
                }
                if status.finished {
                    Text(status.detail).font(Studio.Fonts.body).foregroundStyle(Studio.muted)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { completionActions(failed: status.stage == .failed) }
                        VStack(alignment: .leading, spacing: 8) { completionActions(failed: status.stage == .failed) }
                    }
                } else {
                    ProgressView(value: status.progress)
                        .progressViewStyle(.linear)
                        .tint(Studio.accent)
                        .accessibilityLabel(Text(status.stage.title))
                    if let progress = status.progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(Studio.Fonts.section.monospacedDigit())
                    }
                    Text(String(localized: "上传期间请保持应用打开"))
                        .font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .padding(Studio.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Studio.background)
    }
    @ViewBuilder private func completionActions(failed: Bool) -> some View {
        if failed {
            Button(String(localized: "重试上传")) { Task { await capture.upload(id) } }
                .buttonStyle(StudioPrimaryButton())
        }
        Button { capture.dismissUploadStatus(id) } label: {
            Text(String(localized: "完成")).frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
        }.buttonStyle(RecordPressStyle())
    }
}

private struct FileShareView: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: files, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
