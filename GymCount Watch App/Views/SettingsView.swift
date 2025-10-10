//
//  SettingsView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import HealthKit

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.presentationMode) var presentationMode
    @State private var tempSettings: AppSettings
    @State private var showingHealthKitAlert = false
    @State private var healthKitStatus: HKAuthorizationStatus = .notDetermined
    
    init() {
        _tempSettings = State(initialValue: DataManager.shared.settings)
    }
    
    // MARK: - HealthKit 状态计算属性
    private var healthKitStatusIcon: String {
        switch healthKitStatus.rawValue {
        case 2:
            return "checkmark.circle.fill"
        case 1:
            return "xmark.circle.fill"
        case 0:
            return "questionmark.circle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
    
    private var healthKitStatusColor: Color {
        switch healthKitStatus.rawValue {
        case 2:
            return .green
        case 1:
            return .red
        case 0:
            return .orange
        default:
            return .orange
        }
    }
    
    private var healthKitStatusText: String {
        switch healthKitStatus.rawValue {
        case 2:
            return "已授权"
        case 1:
            return "已拒绝"
        case 0:
            return "未确定"
        default:
            return "未知(\(healthKitStatus.rawValue))"
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // 默认重量设置
                Section(header: Text(NSLocalizedString("weight", comment: "重量"))) {
                    HStack {
                        Text(NSLocalizedString("default_weight", comment: "默认重量"))
                        Spacer()
                        Text("\(Int(tempSettings.defaultWeight)) \(NSLocalizedString("kg", comment: "公斤"))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Button(action: {
                            if tempSettings.defaultWeight > 0 {
                                tempSettings.defaultWeight -= 2.5
                            }
                        }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        Button(action: {
                            tempSettings.defaultWeight += 2.5
                        }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // 用户体重设置
                Section(header: Text(NSLocalizedString("user_info", comment: "用户信息"))) {
                    HStack {
                        Text(NSLocalizedString("my_weight", comment: "我的体重"))
                        Spacer()
                        Text("\(Int(tempSettings.userBodyWeight)) \(NSLocalizedString("kg", comment: "公斤"))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Button(action: {
                            if tempSettings.userBodyWeight > 30 {
                                tempSettings.userBodyWeight -= 1.0
                            }
                        }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        Button(action: {
                            if tempSettings.userBodyWeight < 200 {
                                tempSettings.userBodyWeight += 1.0
                            }
                        }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Text(NSLocalizedString("calorie_calculation_note", comment: "用于更准确的卡路里计算"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // HealthKit 设置
                Section(header: Text("Apple Watch 运动圆环")) {
                    // HealthKit 同步开关
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                        Text("同步到运动圆环")
                        Spacer()
                        Toggle("", isOn: $tempSettings.healthKitSyncEnabled)
                    }
                    
                    if tempSettings.healthKitSyncEnabled {
                        // 自动同步开关
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.blue)
                            Text("自动同步")
                            Spacer()
                            Toggle("", isOn: $tempSettings.autoSyncToHealthKit)
                        }
                        
                        // 权限状态
                        HStack {
                            Image(systemName: healthKitStatusIcon)
                                .foregroundColor(healthKitStatusColor)
                            Text("权限状态")
                            Spacer()
                            Text(healthKitStatusText)
                                .foregroundColor(.secondary)
                        }
                        
                        // 手动同步按钮
                        Button(action: {
                            Task {
                                await dataManager.syncAllWorkoutsToHealthKit()
                            }
                        }) {
                            HStack {
                                Image(systemName: "icloud.and.arrow.up")
                                    .foregroundColor(.blue)
                                Text("立即同步所有记录")
                                Spacer()
                            }
                        }
                        .disabled(!tempSettings.healthKitSyncEnabled)
                        
                        // 请求权限按钮
                        if healthKitStatus.rawValue != 2 {
                            Button(action: {
                                Task {
                                    await dataManager.requestHealthKitPermission()
                                    healthKitStatus = dataManager.getHealthKitAuthorizationStatus()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "lock.open")
                                        .foregroundColor(.orange)
                                    Text("请求 HealthKit 权限")
                                    Spacer()
                                }
                            }
                        }
                        
                        // 调试按钮
                        // Button(action: {
                        //     dataManager.debugHealthKitStatus()
                        // }) {
                        //     HStack {
                        //         Image(systemName: "bug")
                        //             .foregroundColor(.gray)
                        //         Text("调试授权状态")
                        //         Spacer()
                        //     }
                        // }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings", comment: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "取消")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "保存")) {
                        dataManager.updateSettings(tempSettings)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            healthKitStatus = dataManager.getHealthKitAuthorizationStatus()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataManager.shared)
}
