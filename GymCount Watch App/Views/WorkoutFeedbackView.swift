import SwiftUI

struct WorkoutFeedbackView: View {
    let workout: WorkoutHistory
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WorkoutFeedbackStore.shared
    @State private var actual = 0
    @State private var confirmed = false
    @State private var entry: WorkoutFeedbackArchive.Entry?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                GymHeader(title: String(localized: "计数反馈"), back: { dismiss() })
                Text(workout.exerciseType.displayName).font(GymStyle.section)
                Text(workout.date, format: .dateTime.month().day().hour().minute())
                    .font(GymStyle.detail).foregroundStyle(.secondary)
                Text(String(localized: "手表记录：\(workout.totalReps) 次"))
                    .font(GymStyle.body)
                if let entry, entry.serverID != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.largeTitle)
                    Text(String(localized: "反馈已提交，谢谢！")).font(GymStyle.body)
                    Text(String(localized: "实际次数：\(entry.actualCount ?? 0) 次")).font(GymStyle.body)
                    Button(String(localized: "完成")) { dismiss() }.buttonStyle(GymActionStyle())
                } else if entry?.recording != nil {
                    Text(String(localized: "实际次数")).font(GymStyle.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        CircleButton(icon: "minus", disabled: actual == 0 || locked) { actual -= 1 }
                            .accessibilityLabel(String(localized: "减少实际次数"))
                        Text("\(actual)").font(GymStyle.counter).monospacedDigit().frame(maxWidth: .infinity)
                            .accessibilityIdentifier("feedback.actual")
                        CircleButton(icon: "plus", disabled: actual == 500 || locked) { actual += 1 }
                            .accessibilityLabel(String(localized: "增加实际次数"))
                    }
                    if entry?.actualCount == nil {
                        Toggle(String(localized: "已核对次数"), isOn: $confirmed).font(GymStyle.body)
                            .disabled(locked)
                        Text(String(localized: "上传本次运动采样和实际次数"))
                            .font(GymStyle.detail).foregroundStyle(.secondary)
                    }
                    if store.errorID == workout.id, let error = store.errorMessage {
                        Text(error).font(GymStyle.caption).foregroundStyle(.orange).accessibilityIdentifier("feedback.error")
                    }
                    if store.uploadingID == workout.id {
                        ProgressView(String(localized: "正在提交…")).font(GymStyle.caption)
                    } else {
                        Button(entry?.pending == true ? String(localized: "重试上传") : String(localized: "提交反馈")) {
                            Task { await store.upload(workout.id, actual: actual) }
                        }
                        .buttonStyle(GymActionStyle(primary: true))
                        .disabled((!confirmed && entry?.pending != true) || store.uploadingID != nil)
                        .accessibilityIdentifier("feedback.submit")
                    }
                } else {
                    Text(String(localized: "此记录没有可上传的采样"))
                        .font(GymStyle.caption).foregroundStyle(.secondary)
                }
            }.gymPageContent(fullWidthHeader: true)
        }
        .gymPage().toolbar(.hidden)
        .onAppear { store.clearError(); reload(); actual = entry?.actualCount ?? min(500, workout.totalReps) }
        .onChange(of: store.revision) { _, _ in reload() }
    }

    private var locked: Bool { entry?.actualCount != nil || store.uploadingID != nil }
    private func reload() { entry = try? store.archive.load(workout.id) }
}

struct WorkoutSavedBanner: View {
    let workout: WorkoutHistory
    let feedback: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(String(localized: "已保存")).font(GymStyle.section).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(String(localized: "关闭"))
            }
            Text(workout.exerciseType.displayName + " · " + String(localized: "\(workout.totalReps) 次"))
                .font(GymStyle.body)
            Button(String(localized: "计数不准？"), action: feedback)
                .font(GymStyle.caption).frame(minHeight: 44).buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.bottom, 4)
        .background(Color(red: 0.06, green: 0.20, blue: 0.13), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.green.opacity(0.4)))
        .padding(.horizontal, 6)
        .accessibilityIdentifier("workout.saved")
    }
}
