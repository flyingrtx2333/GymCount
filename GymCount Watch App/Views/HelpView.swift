//
//  HelpView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.presentationMode) var presentationMode

    private let sections: [(icon: String, title: String, key: String, items: [String])] = [
        (icon: "figure.strengthtraining.traditional", title: String(localized: "开始训练"), key: "training", items: [
            String(localized: "选择卧推、深蹲或硬拉，点「开始」。"),
            String(localized: "按实际器械重量设置，佩戴手表完成动作。"),
            String(localized: "各组自动记录；换动作或重量时点顶部。"),
            String(localized: "用＋／－核对本组次数，全部完成后点「结束」。")
        ]),
        (icon: "waveform", title: "Siri", key: "siri", items: [
            String(localized: "对手表说「开始健身计数」，再选择动作。"),
            String(localized: "也可以说「用健身计数开始卧推」。"),
            String(localized: "完成后说「结束健身计数」。")
        ]),
        (icon: "list.bullet.rectangle", title: String(localized: "查看记录"), key: "records", items: [
            String(localized: "在手表首页打开历史，查看已保存的训练。"),
            String(localized: "在 iPhone 的「记录」页查看、补记和编辑训练。"),
            String(localized: "记录未出现时，在手机设置中点「手表同步」。")
        ]),
        (icon: "heart", title: String(localized: "健康同步"), key: "health", items: [
            String(localized: "在设置中开启「同步到运动圆环」，允许写入体能训练。"),
            String(localized: "需要补传时，点「立即同步所有记录」。")
        ]),
        (icon: "hand.tap", title: String(localized: "计数核对"), key: "review", items: [
            String(localized: "自动计数在结束时核准，请按实际完成次数核对。"),
            String(localized: "保存后，可从结果提示进入「计数反馈」。")
        ])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GymStyle.spacing) {
                    ForEach(sections, id: \.key) { section in
                        HelpCard(
                            icon: section.icon,
                            title: section.title,
                            items: section.items
                        )
                    }
                }
                .gymPageContent()
            }
            .navigationBarBackButtonHidden(true)
            .gymPage()
            .gymNavigationTitle(NSLocalizedString("help_title", comment: "使用帮助"), back: { presentationMode.wrappedValue.dismiss() })
        }
    }
}

// MARK: - 帮助卡片

struct HelpCard: View {
    let icon: String
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题行
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(GymStyle.detail)
                    .foregroundStyle(GymStyle.accent)
                Text(title)
                    .font(GymStyle.button)
                    .foregroundColor(GymStyle.ink)
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
        )
    }
}

#Preview {
    HelpView()
}
