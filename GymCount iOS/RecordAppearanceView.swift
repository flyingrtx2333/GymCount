import SwiftUI

struct RecordAppearanceView: View {
    @AppStorage("records.appearance") private var appearance = RecordAppearance.system.rawValue
    @AppStorage("records.palette") private var palette = RecordPalette.platinum.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var widthClass
    private var selected: RecordPalette { RecordPalette(rawValue: palette) ?? .platinum }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : widthClass == .regular ? 3 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Studio.spacing) {
                Group {
                    if typeSize.isAccessibilitySize { modePicker.pickerStyle(.menu).font(Studio.Fonts.body) }
                    else { modePicker.pickerStyle(.segmented) }
                }.frame(minHeight: Studio.controlHeight).accessibilityIdentifier("appearance-mode")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(RecordPalette.allCases) { choice in
                        Button { palette = choice.rawValue } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 0) {
                                    preview(choice.colors(dark: false), dark: false)
                                    preview(choice.colors(dark: true), dark: true)
                                }.clipShape(RoundedRectangle(cornerRadius: Studio.controlRadius))
                                    .overlay(RoundedRectangle(cornerRadius: Studio.controlRadius).stroke(Studio.line, lineWidth: Studio.hairline))
                                    .accessibilityHidden(true)
                                HStack(spacing: 8) {
                                    Text(choice.title).font(Studio.Fonts.body.weight(.medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Image(systemName: selected == choice ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected == choice ? Studio.accent : Studio.muted)
                                        .font(.system(size: 18))
                                }.foregroundStyle(Studio.ink)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Studio.surface, in: RoundedRectangle(cornerRadius: Studio.mediaRadius))
                                .overlay(RoundedRectangle(cornerRadius: Studio.mediaRadius)
                                    .stroke(selected == choice ? Studio.accent : Studio.line, lineWidth: selected == choice ? 1.5 : Studio.hairline))
                                .contentShape(RoundedRectangle(cornerRadius: Studio.mediaRadius))
                        }.buttonStyle(RecordPressStyle())
                            .accessibilityElement(children: .ignore).accessibilityLabel(choice.title)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(selected == choice ? .isSelected : [])
                            .accessibilityIdentifier("appearance-palette-" + choice.rawValue)
                    }
                }
            }.padding(.horizontal, Studio.inset).padding(.vertical, Studio.spacing)
        }.recordCanvasSpacing().background(Studio.background)
            .navigationTitle(String(localized: "外观")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("appearance-page")
    }

    private var modePicker: some View {
        Picker(String(localized: "模式"), selection: $appearance) {
            ForEach(RecordAppearance.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
        }
    }

    private func preview(_ colors: RecordPalette.Colors, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1).fill(color(colors.ink)).frame(width: 20, height: 4)
                Spacer(minLength: 0)
                Image(systemName: dark ? "moon.fill" : "sun.max.fill").font(.system(size: 8)).foregroundStyle(color(colors.muted))
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach([12.0, 23.0, 17.0, 30.0], id: \.self) { height in
                    RoundedRectangle(cornerRadius: 2).fill(color(colors.accent)).frame(maxWidth: .infinity).frame(height: height)
                }
            }.frame(height: 30)
            Rectangle().fill(color(colors.line)).frame(height: 1)
        }.padding(9).frame(maxWidth: .infinity).frame(height: 84).background(color(colors.background))
    }
    private func color(_ hex: UInt32) -> Color { Color(uiColor: Studio.uiColor(hex)) }
}
