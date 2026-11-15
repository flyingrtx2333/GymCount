import SwiftUI
import UIKit

enum RecordPalette: String, CaseIterable, Identifiable, Sendable {
    case platinum, onyx, mist, pine, dusk, rose
    var id: String { rawValue }
    var title: String {
        switch self {
        case .platinum: String(localized: "白金")
        case .onyx: String(localized: "曜黑")
        case .mist: String(localized: "雾蓝")
        case .pine: String(localized: "松绿")
        case .dusk: String(localized: "暮紫")
        case .rose: String(localized: "玫瑰")
        }
    }

    enum Role: CaseIterable, Sendable { case background, surface, ink, muted, accent, line, onAccent }
    struct Colors: Sendable {
        let background, surface, ink, muted, accent, line, onAccent: UInt32
        func value(_ role: Role) -> UInt32 {
            switch role {
            case .background: background
            case .surface: surface
            case .ink: ink
            case .muted: muted
            case .accent: accent
            case .line: line
            case .onAccent: onAccent
            }
        }
    }
    func colors(dark: Bool) -> Colors {
        switch (self, dark) {
        case (.platinum, false): Colors(background: 0xF7F5EF, surface: 0xFFFFFF, ink: 0x252722, muted: 0x6A6D65, accent: 0x806124, line: 0xE4E1D7, onAccent: 0xFFFFFF)
        case (.platinum, true): Colors(background: 0x161614, surface: 0x232320, ink: 0xF4F1E8, muted: 0xABA99F, accent: 0xD5BE86, line: 0x3B3B35, onAccent: 0x222019)
        case (.onyx, false): Colors(background: 0xF6F6F7, surface: 0xFFFFFF, ink: 0x222327, muted: 0x666870, accent: 0x454750, line: 0xDEDFE3, onAccent: 0xFFFFFF)
        case (.onyx, true): Colors(background: 0x000000, surface: 0x171719, ink: 0xF3F3F5, muted: 0xA5A5AD, accent: 0xD7D8DE, line: 0x313135, onAccent: 0x141416)
        case (.mist, false): Colors(background: 0xF2F5F8, surface: 0xFFFFFF, ink: 0x1F2A37, muted: 0x5E6D7B, accent: 0x2D6188, line: 0xDCE5EE, onAccent: 0xFFFFFF)
        case (.mist, true): Colors(background: 0x101923, surface: 0x1B2836, ink: 0xEDF4FA, muted: 0xA3B5C5, accent: 0x8BBFE6, line: 0x334454, onAccent: 0x122232)
        case (.pine, false): Colors(background: 0xF2F6F2, surface: 0xFFFFFF, ink: 0x22352D, muted: 0x5E7266, accent: 0x32674F, line: 0xDBE6DE, onAccent: 0xFFFFFF)
        case (.pine, true): Colors(background: 0x111D18, surface: 0x1B2B23, ink: 0xEAF4ED, muted: 0xA4B9AB, accent: 0x91C7A4, line: 0x324A3D, onAccent: 0x11251A)
        case (.dusk, false): Colors(background: 0xF7F3F9, surface: 0xFFFFFF, ink: 0x332A3D, muted: 0x75677F, accent: 0x75508B, line: 0xE7DDEB, onAccent: 0xFFFFFF)
        case (.dusk, true): Colors(background: 0x1D1724, surface: 0x2A2233, ink: 0xF2EBF8, muted: 0xBAA9C7, accent: 0xC2A2DD, line: 0x483A55, onAccent: 0x251831)
        case (.rose, false): Colors(background: 0xFAF3F3, surface: 0xFFFFFF, ink: 0x3E2A30, muted: 0x7D646B, accent: 0x94556A, line: 0xECDDE2, onAccent: 0xFFFFFF)
        case (.rose, true): Colors(background: 0x23171C, surface: 0x322129, ink: 0xFAEDF1, muted: 0xC5A5B1, accent: 0xE4A6BC, line: 0x533A45, onAccent: 0x301C24)
        }
    }
}

// UIKit and SwiftUI share the same palette without global mutable colors or
// reading preferences in drawing code. Trait changes only occur on selection.
struct RecordPaletteTrait: UITraitDefinition {
    static let defaultValue = RecordPalette.platinum
    static let affectsColorAppearance = true
}

private struct RecordPaletteKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = RecordPalette.platinum
    static func read(from traitCollection: UITraitCollection) -> RecordPalette {
        traitCollection[RecordPaletteTrait.self]
    }
    static func write(to mutableTraits: inout UIMutableTraits, value: RecordPalette) {
        mutableTraits[RecordPaletteTrait.self] = value
    }
}

extension EnvironmentValues {
    var recordPalette: RecordPalette {
        get { self[RecordPaletteKey.self] }
        set { self[RecordPaletteKey.self] = newValue }
    }
}
