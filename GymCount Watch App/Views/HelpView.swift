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
                        title: "功能介绍",
                        content: [
                            "• 支持卧推和深蹲计数",
                            "• 自动运动检测（可选）",
                            "• 重量记录和调整",
                            "• 锻炼历史统计",
                            "• 触觉反馈提醒"
                        ]
                    )
                    
                    // 使用方法
                    HelpSection(
                        title: "使用方法",
                        content: [
                            "1. 选择锻炼类型（卧推/深蹲）",
                            "2. 点击开始按钮开始锻炼",
                            "3. 每次完成动作后点击+按钮计数",
                            "4. 锻炼结束后点击停止按钮",
                            "5. 查看历史记录了解进步"
                        ]
                    )
                    
                    // 自动检测
                    HelpSection(
                        title: "自动检测",
                        content: [
                            "• 在设置中开启自动检测",
                            "• 手表会自动识别运动动作",
                            "• 绿色指示灯表示检测正常",
                            "• 建议在安静环境下使用"
                        ]
                    )
                    
                    // 注意事项
                    HelpSection(
                        title: "注意事项",
                        content: [
                            "• 确保手表佩戴牢固",
                            "• 避免剧烈晃动影响检测",
                            "• 定期查看历史记录",
                            "• 根据个人情况调整重量"
                        ]
                    )
                }
                .padding()
            }
            .navigationTitle("使用帮助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
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
