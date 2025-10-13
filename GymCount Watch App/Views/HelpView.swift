//
//  HelpView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 功能介绍
                    HelpSection(
                        title: NSLocalizedString("help_features_title", comment: "功能介绍"),
                        content: [
                            NSLocalizedString("help_feature_1", comment: "• 支持卧推和深蹲计数"),
                            NSLocalizedString("help_feature_2", comment: "• 自动运动检测（可选）"),
                            NSLocalizedString("help_feature_3", comment: "• 重量记录和调整"),
                            NSLocalizedString("help_feature_4", comment: "• 锻炼历史统计"),
                            NSLocalizedString("help_feature_5", comment: "• 触觉反馈提醒")
                        ]
                    )
                    
                    // 使用方法
                    HelpSection(
                        title: NSLocalizedString("help_usage_title", comment: "使用方法"),
                        content: [
                            NSLocalizedString("help_usage_1", comment: "1. 选择锻炼类型（卧推/深蹲）"),
                            NSLocalizedString("help_usage_2", comment: "2. 点击开始按钮开始锻炼"),
                            NSLocalizedString("help_usage_3", comment: "3. 每次完成动作后点击+按钮计数"),
                            NSLocalizedString("help_usage_4", comment: "4. 锻炼结束后点击停止按钮"),
                            NSLocalizedString("help_usage_5", comment: "5. 查看历史记录了解进步")
                        ]
                    )
                    
                    // 自动检测
                    HelpSection(
                        title: NSLocalizedString("help_auto_detection_title", comment: "自动检测"),
                        content: [
                            NSLocalizedString("help_auto_1", comment: "• 在设置中开启自动检测"),
                            NSLocalizedString("help_auto_2", comment: "• 手表会自动识别运动动作"),
                            NSLocalizedString("help_auto_3", comment: "• 绿色指示灯表示检测正常"),
                            NSLocalizedString("help_auto_4", comment: "• 建议在安静环境下使用")
                        ]
                    )
                    
                    // 注意事项
                    HelpSection(
                        title: NSLocalizedString("help_notes_title", comment: "注意事项"),
                        content: [
                            NSLocalizedString("help_note_1", comment: "• 确保手表佩戴牢固"),
                            NSLocalizedString("help_note_2", comment: "• 避免剧烈晃动影响检测"),
                            NSLocalizedString("help_note_3", comment: "• 定期查看历史记录"),
                            NSLocalizedString("help_note_4", comment: "• 根据个人情况调整重量")
                        ]
                    )
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("help_title", comment: "使用帮助"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("done", comment: "完成")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct HelpSection: View {
    let title: String
    let content: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            ForEach(content, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HelpView()
}
