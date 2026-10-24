import SwiftUI
import UIKit

// One semantic palette shared by records, tools and upload sheets.
enum Studio {
    static let title = Font.largeTitle.weight(.semibold)
    static let body = Font.body
    static let button = Font.headline
    static let detail = Font.subheadline
    static let inset: CGFloat = 20
    static let spacing: CGFloat = 16
    static let buttonHeight: CGFloat = 48
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0xF7F5EF, 0x161614)
    static let surface = adaptive(0xFFFFFF, 0x232320)
    static let ink = adaptive(0x252722, 0xF4F1E8)
    static let muted = adaptive(0x6A6D65, 0xABA99F)
    static let accent = adaptive(0x806124, 0xD5BE86)
    static let gold = adaptive(0xE8D8B3, 0x514830)
    static let line = adaptive(0xE4E1D7, 0x3B3B35)
    static let onAccent = adaptive(0xFFFFFF, 0x222019)
}

enum RecordAppearance: String, CaseIterable {
    case system, light, dark
    var title: String { switch self {
        case .system: String(localized: "跟随系统")
        case .light: String(localized: "浅色")
        case .dark: String(localized: "深色")
    } }
    var scheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
}

extension ExerciseType {
    var recordName: String { switch self {
        case .benchPress: String(localized: "卧推")
        case .squat: String(localized: "深蹲")
        case .deadlift: String(localized: "硬拉")
    } }
}

extension View {
    func recordListStyle() -> some View {
        self.scrollContentBackground(.hidden).background(Studio.background).listSectionSpacing(16)
            .listRowSeparatorTint(Studio.line).tint(Studio.accent)
    }
}

struct RecordMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Studio.muted)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Studio.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct RecordOverviewMetric: View {
    let title: String
    let value: String
    var unit: String? = nil
    @ScaledMetric(relativeTo: .title) private var numberSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) { number; unitLabel }
                VStack(alignment: .leading, spacing: 2) { number; unitLabel }
            }
            Text(title).font(.caption).foregroundStyle(Studio.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
    private var number: some View {
        Text(value).font(.system(size: numberSize, weight: .semibold, design: .rounded))
            .monospacedDigit().foregroundStyle(Studio.ink).fixedSize(horizontal: true, vertical: false)
    }
    @ViewBuilder private var unitLabel: some View {
        if let unit { Text(unit).font(.caption).foregroundStyle(Studio.muted) }
    }
}

// The same vector asset names are owned by shared ExerciseType and used by Watch.
struct RecordExerciseIcon: View {
    let exercise: ExerciseType
    var size: CGFloat = 24
    var body: some View {
        Image(exercise.icon).renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size).foregroundStyle(Studio.accent)
            .accessibilityHidden(true)
    }
}

struct RecordExerciseLabel: View {
    let exercise: ExerciseType
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: 8) {
            RecordExerciseIcon(exercise: exercise, size: size)
            Text(exercise.recordName).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}

struct RecordFilterLabel: View {
    let title: String
    var exercise: ExerciseType? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let exercise { RecordExerciseIcon(exercise: exercise, size: 20) }
            Text(title).font(.subheadline.weight(.medium))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.muted)
        }.foregroundStyle(Studio.ink).frame(minHeight: 44).contentShape(Rectangle())
    }
}

struct StudioPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Studio.onAccent)
            .padding(.horizontal, 20).frame(minHeight: 48)
            .background(Studio.accent, in: RoundedRectangle(cornerRadius: 14))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
struct StudioSecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Studio.accent)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Studio.line, lineWidth: 1))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}

func recordDate(_ date: Date) -> String {
    date.formatted(Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        ? .dateTime.month().day().weekday() : .dateTime.year().month().day())
}

// M2: one interruptible, non-bouncy motion policy for the records workspace.
enum RecordMotion {
    static func animation(reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.32, bounce: 0) }
    static func row(reduced: Bool) -> AnyTransition { reduced ? .identity : .move(edge: .top).combined(with: .opacity) }
}

struct RecordPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Studio.accent)
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.76 : 1)
            .scaleEffect(reduced || !configuration.isPressed ? 1 : 0.99)
            .animation(RecordMotion.animation(reduced: reduced), value: configuration.isPressed)
    }
}

struct RecordFocusOutline: ViewModifier {
    let focused: Bool
    let space: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        content.overlay {
            if focused {
                RoundedRectangle(cornerRadius: 8).stroke(Studio.accent, lineWidth: 1)
                    .matchedGeometryEffect(id: "entry-focus", in: space, isSource: true)
                    .allowsHitTesting(false)
            }
        }.animation(RecordMotion.animation(reduced: reduced), value: focused)
    }
}

extension View {
    func recordPage(active: Bool, reduced: Bool) -> some View {
        self.opacity(active ? 1 : 0).offset(x: active || reduced ? 0 : 18)
            .allowsHitTesting(active).accessibilityHidden(!active)
            .animation(RecordMotion.animation(reduced: reduced), value: active)
    }
}
