//
//  HelpView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.presentationMode) var presentationMode

    private let sections: [(icon: String, color: Color, title: String, key: String, items: [String])] = [
        (
            icon: "star.fill",
            color: .yellow,
            title: NSLocalizedString("help_features_title", comment: "功能介绍"),
            key: "features",
            items: [
                NSLocalizedString("help_feature_1", comment: "• 支持卧推和深蹲计数"),
                NSLocalizedString("help_feature_2", comment: "• 自动运动检测（可选）"),
                NSLocalizedString("help_feature_3", comment: "• 重量记录和调整"),
                NSLocalizedString("help_feature_4", comment: "• 锻炼历史统计"),
                NSLocalizedString("help_feature_5", comment: "• 触觉反馈提醒")
            ]
        ),
        (
            icon: "hand.tap.fill",
            color: .blue,
            title: NSLocalizedString("help_usage_title", comment: "使用方法"),
            key: "usage",
            items: [
                NSLocalizedString("help_usage_1", comment: "1. 选择锻炼类型"),
                NSLocalizedString("help_usage_2", comment: "2. 点击开始按钮"),
                NSLocalizedString("help_usage_3", comment: "3. 点击+按钮计数"),
                NSLocalizedString("help_usage_4", comment: "4. 点击停止完成"),
                NSLocalizedString("help_usage_5", comment: "5. 查看历史记录")
            ]
        ),
        (
            icon: "waveform.path",
            color: .green,
            title: NSLocalizedString("help_auto_detection_title", comment: "自动检测"),
            key: "detect",
            items: [
                NSLocalizedString("help_auto_1", comment: "• 在设置中开启自动检测"),
                NSLocalizedString("help_auto_2", comment: "• 手表会自动识别运动动作"),
                NSLocalizedString("help_auto_3", comment: "• 绿色指示灯表示检测正常"),
                NSLocalizedString("help_auto_4", comment: "• 建议在安静环境下使用")
            ]
        ),
        (
            icon: "mic.fill",
            color: .purple,
            title: NSLocalizedString("help_shortcuts_title", comment: "快捷指令"),
            key: "shortcuts",
            items: [
                NSLocalizedString("help_shortcuts_1", comment: "• 在快捷指令应用中创建"),
                NSLocalizedString("help_shortcuts_2", comment: "• 对 Siri 说：开始记录深蹲"),
                NSLocalizedString("help_shortcuts_3", comment: "• 或创建自定义快捷指令"),
                NSLocalizedString("help_shortcuts_4", comment: "• 详细指南见应用文档")
            ]
        ),
        (
            icon: "exclamationmark.triangle.fill",
            color: .orange,
            title: NSLocalizedString("help_notes_title", comment: "注意事项"),
            key: "notes",
            items: [
                NSLocalizedString("help_note_1", comment: "• 确保手表佩戴牢固"),
                NSLocalizedString("help_note_2", comment: "• 避免剧烈晃动影响检测"),
                NSLocalizedString("help_note_3", comment: "• 定期查看历史记录"),
                NSLocalizedString("help_note_4", comment: "• 根据情况调整重量")
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GymStyle.spacing) {
                    GymHeader(title: NSLocalizedString("help_title", comment: "使用帮助"),
                              back: { presentationMode.wrappedValue.dismiss() })
                    ForEach(sections, id: \.key) { section in
                        HelpCard(
                            icon: section.icon,
                            iconColor: section.color,
                            title: section.title,
                            items: section.items
                        )
                    }
                }
                .gymPageContent(fullWidthHeader: true)
            }
            .navigationTitle(NSLocalizedString("help_title", comment: "使用帮助"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden)
            .gymPage()
        }
    }
}

// MARK: - 帮助卡片

struct HelpCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题行
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(GymStyle.detail)
                    .foregroundStyle(GymStyle.mint)
                Text(title)
                    .font(GymStyle.button)
                    .foregroundColor(.white)
            }

            // 内容
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(GymStyle.detail)
                        .foregroundStyle(GymStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(GymStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.clear, lineWidth: 0)
                )
        )
    }
}

#Preview {
    HelpView()
}
