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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AccessibilityFocusState private var resultFocused: Bool
    @ScaledMetric(relativeTo: .caption) private var textSize: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.green).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "已保存"))
                        .font(.system(size: textSize, weight: .semibold))
                    Text(workout.exerciseType.displayName + " · " + String(localized: "\(workout.totalReps) 次"))
                        .font(.system(size: textSize)).lineLimit(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($resultFocused)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(WorkoutSavedButtonStyle())
                .accessibilityLabel(String(localized: "关闭"))
                .accessibilityIdentifier("workout.saved.close")
            }
            .padding(.leading, 10).padding(.trailing, 2).frame(minHeight: 44)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5).accessibilityHidden(true)
            Button(action: feedback) {
                HStack {
                    Text(String(localized: "计数反馈")).font(.system(size: textSize))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(WorkoutSavedButtonStyle())
            .accessibilityIdentifier("workout.saved.feedback")
        }
        .foregroundStyle(.white)
        .background(Color(red: 26 / 255, green: 28 / 255, blue: 29 / 255), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 8)
        .onAppear { if voiceOver { resultFocused = true } }
    }
}

enum WorkoutSavedMotion {
    static func animation(isPresented: Bool, reduced: Bool) -> Animation {
        if reduced { return .easeOut(duration: 0.12) }
        return isPresented ? .spring(response: 0.28, dampingFraction: 0.92) : .easeInOut(duration: 0.16)
    }

    static func transition(reduced: Bool) -> AnyTransition {
        guard !reduced else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 8).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
            removal: .offset(y: -3).combined(with: .opacity))
    }
}

private struct WorkoutSavedButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.1), value: configuration.isPressed)
    }
}
