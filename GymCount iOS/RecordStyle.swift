import SwiftUI
import UIKit

// Shipping iOS visual contract. See docs/ios-design-system.md.
enum Studio {
    static let inset: CGFloat = 16
    static let spacing: CGFloat = 16
    static let wideInset: CGFloat = 28
    static let wideSidebarInset: CGFloat = 24
    static let wideTopInset: CGFloat = 8
    static let controlHeight: CGFloat = 44
    static let rowHeight: CGFloat = 68
    static let controlRadius: CGFloat = 8
    static let mediaRadius: CGFloat = 12
    static let hairline: CGFloat = 0.5
    enum Fonts {
        static let title = Font.title2.weight(.semibold)
        static let modalTitle = Font.title3.weight(.semibold)
        static let section = Font.subheadline.weight(.semibold)
        static let body = Font.subheadline
        static let control = Font.caption.weight(.medium)
        static let primaryAction = Font.subheadline.weight(.semibold)
        static let metric = Font.title2.weight(.medium)
        static let rowMetric = Font.title3.weight(.medium)
        static let caption = Font.caption
        static let axis = Font.caption2
    }
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
    static let line = adaptive(0xE4E1D7, 0x3B3B35)
    static let onAccent = adaptive(0xFFFFFF, 0x222019)
}

// All three root pages share the same title metrics and action alignment.
// Only constrained widths and accessibility text sizes add a second row.
struct RecordPageHeader<Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let identifier: String
    private let actions: Actions

    init(title: String, identifier: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.identifier = identifier
        self.actions = actions()
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        heading.fixedSize()
                        Spacer(minLength: 8)
                        actions.fixedSize()
                    }
                    stacked
                }
            }
        }.frame(maxWidth: .infinity, minHeight: Studio.controlHeight, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Studio.inset).background(Studio.background)
            .font(Studio.Fonts.control).foregroundStyle(Studio.ink).buttonStyle(RecordPressStyle())
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            actions.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var heading: some View {
        Text(title).font(Studio.Fonts.title)
            .fixedSize(horizontal: false, vertical: true).frame(minHeight: Studio.controlHeight, alignment: .leading)
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
    }
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

// Stored in the app's selected defaults suite, independently of workout data.
struct RecordViewPreferences: Codable {
    var filter: RecordFilter
    var metric: String = ""
    var granularity: String = "automatic"
    var collapsed = false
    var previousFilter: RecordFilter?

    static func decode(_ data: Data, fallback: Self) -> Self {
        guard var value = try? JSONDecoder().decode(Self.self, from: data),
              value.filter.start.timeIntervalSinceReferenceDate.isFinite,
              value.filter.end.timeIntervalSinceReferenceDate.isFinite,
              value.filter.start <= value.filter.end else { return fallback }
        if let previous = value.previousFilter,
           !previous.start.timeIntervalSinceReferenceDate.isFinite || !previous.end.timeIntervalSinceReferenceDate.isFinite || previous.start > previous.end {
            value.previousFilter = nil
        }
        return value
    }
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

extension ExerciseType {
    var recordName: String { switch self {
        case .benchPress: String(localized: "卧推")
        case .squat: String(localized: "深蹲")
        case .deadlift: String(localized: "硬拉")
    } }
}

extension View {
    func recordCanvasSpacing(sidebar: Bool = false, wide: Bool? = nil) -> some View {
        modifier(RecordCanvasSpacing(sidebar: sidebar, wide: wide))
    }
    func recordListStyle() -> some View {
        self.scrollContentBackground(.hidden).background(Studio.background).listSectionSpacing(Studio.spacing)
            .listRowSeparatorTint(Studio.line).tint(Studio.accent)
    }
    func recordSectionStyle() -> some View {
        self.listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: Studio.inset, bottom: 8, trailing: Studio.inset))
    }
}

private struct RecordCanvasSpacing: ViewModifier {
    @Environment(\.horizontalSizeClass) private var widthClass
    var sidebar: Bool
    var wide: Bool?
    func body(content: Content) -> some View {
        let expanded = wide ?? (widthClass == .regular)
        content
            .padding(.horizontal, expanded ? (sidebar ? Studio.wideSidebarInset : Studio.wideInset) - Studio.inset : 0)
            .padding(.top, expanded ? Studio.wideTopInset : 0)
            .background(Studio.background)
    }
}

struct RecordSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(Studio.Fonts.section).foregroundStyle(Studio.ink)
            .textCase(nil).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

// A missing local measurement should not dominate a populated page.
struct RecordInlineState: View {
    let title: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(Studio.Fonts.body).accessibilityHidden(true)
            Text(title).font(Studio.Fonts.body).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(Studio.muted)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct RecordMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
            RecordNumberText(value: value).foregroundStyle(Studio.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

// Keep localized values intact while giving numerals and units different emphasis.
struct RecordNumberText: View {
    let value: String
    var numberFont: Font = Studio.Fonts.metric
    var unitFont: Font = Studio.Fonts.caption

    private var attributed: AttributedString {
        var text = AttributedString(value)
        text.font = unitFont
        for index in text.characters.indices {
            let character = text.characters[index]
            if character.isNumber || ".,:٫٬".contains(character) {
                let next = text.characters.index(after: index)
                text[index..<next].font = numberFont
            }
        }
        return text
    }
    var body: some View { Text(attributed).monospacedDigit() }
}

// The same vector asset names are owned by shared ExerciseType and used by Watch.
struct RecordExerciseIcon: View {
    let exercise: ExerciseType
    var size: CGFloat = 24
    var color: Color = Studio.accent
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    private var dimension: CGFloat { max(26, size) * min(1.3, max(1, textScale)) }
    var body: some View {
        Image(exercise.icon).renderingMode(.template).resizable().scaledToFit()
            .frame(width: dimension, height: dimension).foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

struct RecordExerciseLabel: View {
    let exercise: ExerciseType
    var size: CGFloat = 24
    var color: Color = Studio.accent
    var body: some View {
        HStack(spacing: 8) {
            RecordExerciseIcon(exercise: exercise, size: size, color: color)
            Text(exercise.recordName).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}

struct RecordFilterLabel: View {
    let title: String
    var exercise: ExerciseType? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let exercise { RecordExerciseIcon(exercise: exercise, size: 20) }
            Text(title).font(Studio.Fonts.control).fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Studio.muted)
        }.foregroundStyle(Studio.ink).frame(minWidth: Studio.controlHeight, minHeight: Studio.controlHeight).contentShape(Rectangle())
    }
}

struct StudioPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Studio.Fonts.primaryAction).foregroundStyle(Studio.onAccent)
            .padding(.horizontal, Studio.inset).frame(minHeight: Studio.controlHeight)
            .background(Studio.accent, in: RoundedRectangle(cornerRadius: Studio.controlRadius))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.76 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.99)
            .animation(RecordMotion.press(reduced: reduceMotion), value: configuration.isPressed)
    }
}
struct StudioSecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Studio.Fonts.primaryAction).foregroundStyle(Studio.accent)
            .padding(.horizontal, Studio.inset).frame(minHeight: Studio.controlHeight)
            .background(Studio.surface, in: RoundedRectangle(cornerRadius: Studio.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Studio.controlRadius).stroke(Studio.line, lineWidth: Studio.hairline))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.76 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.99)
            .animation(RecordMotion.press(reduced: reduceMotion), value: configuration.isPressed)
    }
}

func recordDate(_ date: Date) -> String {
    date.formatted(Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        ? .dateTime.month().day().weekday() : .dateTime.year().month().day())
}

func recordChartDateFormat(first: Date?, last: Date?) -> Date.FormatStyle {
    guard let first, let last else { return .dateTime.month(.twoDigits).day(.twoDigits) }
    let calendar = Calendar.current
    let firstYear = calendar.component(.year, from: first)
    let showYear = firstYear != calendar.component(.year, from: last) || firstYear != calendar.component(.year, from: Date())
    guard showYear else { return .dateTime.month(.twoDigits).day(.twoDigits) }
    if last.timeIntervalSince(first) > 180 * 86400 { return .dateTime.year(.twoDigits).month(.twoDigits) }
    return .dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits)
}

// M2: one interruptible, non-bouncy motion policy for the records workspace.
enum RecordMotion {
    static func animation(reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.32, bounce: 0) }
    static func row(reduced: Bool) -> AnyTransition { reduced ? .identity : .move(edge: .top).combined(with: .opacity) }
    static func press(reduced: Bool) -> Animation? { reduced ? nil : .easeOut(duration: 0.16) }
}

struct RecordPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Studio.accent)
            .font(Studio.Fonts.control)
            .frame(minWidth: Studio.controlHeight, minHeight: Studio.controlHeight)
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.76 : 1)
            .scaleEffect(reduced || !configuration.isPressed ? 1 : 0.99)
            .animation(RecordMotion.press(reduced: reduced), value: configuration.isPressed)
    }
}

struct RecordFocusOutline: ViewModifier {
    let focused: Bool
    let space: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        content.overlay {
            if focused {
                RoundedRectangle(cornerRadius: Studio.controlRadius).stroke(Studio.accent, lineWidth: 1)
                    .matchedGeometryEffect(id: "entry-focus", in: space, isSource: true)
                    .allowsHitTesting(false)
            }
        }.animation(RecordMotion.animation(reduced: reduced), value: focused)
    }
}
