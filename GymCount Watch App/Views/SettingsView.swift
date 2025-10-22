//
//  SettingsView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import HealthKit
import Intents

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var notificationManager: NotificationManager
    @Environment(\.presentationMode) var presentationMode
    @State private var tempSettings: AppSettings
    @State private var showingHealthKitAlert = false
    @State private var healthKitStatus: HKAuthorizationStatus = .notDetermined
    @State private var siriStatus: INSiriAuthorizationStatus = .notDetermined

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
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
            return NSLocalizedString("authorized", comment: "已授权")
        case 1:
            return NSLocalizedString("denied", comment: "已拒绝")
        case 0:
            return NSLocalizedString("not_determined", comment: "未确定")
        default:
            return NSLocalizedString("unknown_status", comment: "未知") + "(\(healthKitStatus.rawValue))"
        }
    }
    
    // MARK: - Siri 状态计算属性
    private var siriStatusIcon: String {
        switch siriStatus {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        case .restricted:
            return "exclamationmark.triangle.fill"
        @unknown default:
            return "questionmark.circle.fill"
        }
    }
    
    private var siriStatusColor: Color {
        switch siriStatus {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        case .restricted:
            return .yellow
        @unknown default:
            return .orange
        }
    }
    
    private var siriStatusText: String {
        switch siriStatus {
        case .authorized:
            return NSLocalizedString("authorized", comment: "已授权")
        case .denied:
            return NSLocalizedString("denied", comment: "已拒绝")
        case .notDetermined:
            return NSLocalizedString("not_determined", comment: "未确定")
        case .restricted:
            return NSLocalizedString("siri_restricted", comment: "受限")
        @unknown default:
            return NSLocalizedString("unknown_status", comment: "未知")
        }
    }
    
    // MARK: - 通知状态计算属性
    private var notificationStatusIcon: String {
        switch notificationManager.authorizationStatus {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        case .provisional:
            return "exclamationmark.circle.fill"
        case .ephemeral:
            return "exclamationmark.circle.fill"
        @unknown default:
            return "questionmark.circle.fill"
        }
    }
    
    private var notificationStatusColor: Color {
        switch notificationManager.authorizationStatus {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        case .provisional:
            return .yellow
        case .ephemeral:
            return .yellow
        @unknown default:
            return .orange
        }
    }
    
    private var notificationStatusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized:
            return NSLocalizedString("authorized", comment: "已授权")
        case .denied:
            return NSLocalizedString("denied", comment: "已拒绝")
        case .notDetermined:
            return NSLocalizedString("not_determined", comment: "未确定")
        case .provisional:
            return NSLocalizedString("provisional", comment: "临时授权")
        case .ephemeral:
            return NSLocalizedString("ephemeral", comment: "临时授权")
        @unknown default:
            return NSLocalizedString("unknown_status", comment: "未知")
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // 默认重量设置
                Section() {
                    HStack {
                        Text(NSLocalizedString("equipment weight", comment: "器械重量"))
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
                Section() {
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
                }
                
                // HealthKit 设置
                Section(header: Text(NSLocalizedString("healthkit_section", comment: "Apple Watch 运动圆环"))) {
                    // HealthKit 同步开关
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                        Text(NSLocalizedString("sync_to_activity_rings", comment: "同步到运动圆环"))
                        Spacer()
                        Toggle("", isOn: $tempSettings.healthKitSyncEnabled)
                    }
                    
                    if tempSettings.healthKitSyncEnabled {
                        // 自动同步开关
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.blue)
                            Text(NSLocalizedString("auto_sync", comment: "自动同步"))
                            Spacer()
                            Toggle("", isOn: $tempSettings.autoSyncToHealthKit)
                        }
                        
                        // 权限状态
                        HStack {
                            Image(systemName: healthKitStatusIcon)
                                .foregroundColor(healthKitStatusColor)
                            Text(NSLocalizedString("permission_status", comment: "权限状态"))
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
                                Text(NSLocalizedString("sync_all_records", comment: "立即同步所有记录"))
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
                                    Text(NSLocalizedString("request_healthkit_permission", comment: "请求 HealthKit 权限"))
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                
                // 通知设置
                Section(header: Text(NSLocalizedString("notification_section", comment: "通知设置"))) {
                    // 通知权限状态
                    HStack {
                        Image(systemName: notificationStatusIcon)
                            .foregroundColor(notificationStatusColor)
                        Text(NSLocalizedString("notification_permission", comment: "通知权限"))
                        Spacer()
                        Text(notificationStatusText)
                            .foregroundColor(.secondary)
                    }
                    
                    // 请求通知权限按钮
                    if notificationManager.authorizationStatus != .authorized {
                        Button(action: {
                            Task {
                                await notificationManager.requestNotificationPermission()
                            }
                        }) {
                            HStack {
                                Image(systemName: "bell.badge")
                                    .foregroundColor(.blue)
                                Text(NSLocalizedString("request_notification_permission", comment: "请求通知权限"))
                                Spacer()
                            }
                        }
                    }
                }
                
                // #if DEBUG
                // Section(header: Text("调试功能")) {
                //     Button(action: {
                //         dataManager.generateRandomBenchPressData()
                //     }) {
                //         HStack {
                //             Image(systemName: "dice")
                //                 .foregroundColor(.purple)
                //             Text("生成随机卧推数据")
                //             Spacer()
                //         }
                //     }
                // }
                // #endif
                
                // 应用版本信息
                Section(header: Text(NSLocalizedString("app_info", comment: "应用信息"))) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text(NSLocalizedString("version", comment: "版本"))
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings", comment: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {presentationMode.wrappedValue.dismiss()}){
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.primary)
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
            notificationManager.checkAuthorizationStatus()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataManager.shared)
        .environmentObject(NotificationManager.shared)
}
