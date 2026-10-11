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
                                Text("相机预览").font(.subheadline)
                            }.foregroundStyle(Studio.muted)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Studio.line, lineWidth: 0.5))
                Picker("动作", selection: $exercise) {
                    Text("杠铃深蹲").tag("squat")
                    Text("卧推").tag("bench_press")
                    Text("硬拉").tag("deadlift")
                    Text("弯举").tag("bicep_curl")
                    Text("非训练动作").tag("other")
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 52)
                .background(Studio.surface, in: RoundedRectangle(cornerRadius: 16))
                .disabled(capture.recording || capture.busy)
                if capture.recording {
                    Text("\(capture.count)").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                }
                if !capture.message.isEmpty, capture.message != "正在准备采集…", capture.message != "采集中" {
                    Text(capture.message).font(.callout)
                }
                Button(capture.recording ? "结束采集" : capture.busy ? "正在准备采集…" : "开始采集") {
                    Task { if capture.recording { await capture.stop() } else { await capture.start(exercise: exercise) } }
                }
                .buttonStyle(StudioPrimaryButton())
                .disabled(capture.busy || !capture.cameraReady)
                if capture.starting {
                    Button("取消启动") { Task { await capture.cancelStart() } }
                        .buttonStyle(StudioSecondaryButton())
                }
                NavigationLink("采集记录") { VideoCaptureHistoryView() }
                    .buttonStyle(StudioSecondaryButton())
            }.padding(Studio.inset)
        }
        .navigationTitle("同步采集")
        .navigationBarTitleDisplayMode(.inline)
        .background(Studio.background)
        .toolbarBackground(Studio.background, for: .navigationBar)
        .tint(Studio.accent)
        .task { await capture.enterCaptureScreen() }
        .onDisappear { capture.leaveCaptureScreen() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await capture.stop(reason: "进入后台，采集已结束") } }
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
    var body: some View {
        List(capture.history) { item in
            NavigationLink { VideoCaptureDetailView(id: item.id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.createdAt.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))
                        Spacer(minLength: 8)
                        Text(item.uploadStatusTitle)
                            .font(.caption)
                            .foregroundStyle(item.cloudUploadComplete ? Studio.accent : Studio.muted)
                    }
                    Text("\(item.videoComplete ? "录像已保存" : "录像未完成") · \(item.sensorComplete ? "采样已接收" : "等待采样")")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = item.error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .listRowBackground(Studio.surface)
            .listRowSeparatorTint(Studio.line)
        }
        .scrollContentBackground(.hidden)
        .background(Studio.background)
        .overlay {
            if capture.history.isEmpty {
                ContentUnavailableView("还没有采集记录", systemImage: "video")
            }
        }
        .navigationTitle("采集记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Studio.background, for: .navigationBar)
    }
}

struct VideoCaptureDetailView: View {
    @EnvironmentObject var capture: PhoneCaptureStore
    let id: UUID
    @State private var player: AVPlayer?
    @State private var actual = 0
    @State private var sharing = false
    @State private var confirmingUpload = false
    var body: some View {
        ScrollView {
            if let item = capture.history.first(where: { $0.id == id }) {
                VStack(spacing: Studio.spacing) {
                    if let player { VideoPlayer(player: player).frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 20)) }
                    Text("手表计数：\(item.detectedCount) 次")
                    Button("标记一次") {
                        if let player {
                            player.pause()
                            capture.markReference(id, at: CMTimeGetSeconds(player.currentTime()))
                            actual = capture.history.first(where: { $0.id == id })?.actualCount ?? actual
                        }
                    }
                    .buttonStyle(StudioPrimaryButton())
                    .disabled(capture.uploading)
                    Text("已标记 \(item.referenceEvents.count) 次").font(.caption)
                    Button("撤销标记") {
                        capture.undoReference(id)
                        actual = capture.history.first(where: { $0.id == id })?.actualCount ?? actual
                    }.buttonStyle(StudioSecondaryButton()).disabled(capture.uploading || item.referenceEvents.isEmpty)
                    Stepper("实际次数：\(actual) 次", value: $actual, in: 0...500)
                        .disabled(capture.uploading)
                        .onChange(of: actual) { _, value in capture.setActual(value, for: id) }
                        .padding(16).background(Studio.surface, in: RoundedRectangle(cornerRadius: 16))
                    if let offset = item.sensorOffsetInVideo {
                        Text("采样起点约 \(offset, specifier: "%.2f") 秒").font(.caption)
                        HStack {
                            Button("对齐 −0.1 秒") { capture.adjustAlignment(id, by: -0.1) }
                            Button("对齐 +0.1 秒") { capture.adjustAlignment(id, by: 0.1) }
                        }.buttonStyle(StudioSecondaryButton()).font(.caption).disabled(capture.uploading)
                    }
                    if !item.sensorComplete {
                        Button("重试接收采样") { Task { await capture.receiveAgain(id) } }
                            .buttonStyle(StudioSecondaryButton())
                    }
                    Button(capture.uploading ? "正在上传…" : "上传录像与采样") { confirmingUpload = true }
                        .buttonStyle(StudioPrimaryButton())
                        .disabled(capture.uploading || !item.sensorComplete || item.actualCount == nil)
                    Button("分享文件") { sharing = true }
                        .buttonStyle(StudioSecondaryButton()).disabled(!item.videoComplete)
                    if let error = item.error {
                        Text(error).foregroundStyle(.red)
                    } else if !capture.message.isEmpty, !capture.message.hasPrefix("正在上传") {
                        Text(capture.message).font(.footnote)
                    }
                }.padding(Studio.inset)
                .onAppear {
                    actual = item.actualCount ?? 0
                    if player == nil { player = AVPlayer(url: capture.videoURL(id)) }
                }
                .sheet(isPresented: $sharing) {
                    FileShareView(files: [capture.videoURL(id), capture.sensorURL(id), capture.folder(id).appendingPathComponent("manifest.json")].filter { FileManager.default.fileExists(atPath: $0.path) })
                }
                .confirmationDialog("实际 \(actual) 次，确认上传？", isPresented: $confirmingUpload, titleVisibility: .visible) {
                    Button("上传 \(actual) 次") {
                        capture.setActual(actual, for: id)
                        Task { await capture.upload(id) }
                    }
                    Button("继续修改", role: .cancel) {}
                }
            }
        }
        .background(Studio.background)
        .navigationTitle("录像核对")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Studio.background, for: .navigationBar)
        .onDisappear { player?.pause() }
    }
}

private struct FileShareView: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: files, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
