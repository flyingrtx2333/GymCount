//
//  GymCountApp.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

@main
struct GymCount_Watch_AppApp: App {
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    
    init() {
        // 注册快捷指令
        GymCountShortcutsProvider.updateAppShortcutParameters()
    }
    
    var body: some Scene {
        WindowGroup {
            if dataManager.isFirstLaunch {
                SplashView()
                    .environmentObject(dataManager)
                    .environmentObject(notificationManager)
                    .onAppear {
                        // 应用启动时请求通知权限
                        Task {
                            await requestInitialPermissions()
                        }
                    }
            } else {
                ContentView()
                    .environmentObject(dataManager)
                    .environmentObject(notificationManager)
                    .onAppear {
                        // 应用启动时请求通知权限
                        Task {
                            await requestInitialPermissions()
                        }
                    }
            }
        }
    }
    
    // MARK: - 请求初始权限
    private func requestInitialPermissions() async {
        print("🔔 开始请求初始权限...")
        
        // 请求通知权限
        let notificationGranted = await notificationManager.requestNotificationPermission()
        print("🔔 通知权限请求完成: \(notificationGranted)")
        
        // 如果通知权限授权成功，设置每日提醒
        if notificationGranted {
            notificationManager.scheduleDailyReminder()
        }
        
        // 请求 HealthKit 权限（如果启用）
        if dataManager.settings.healthKitSyncEnabled {
            print("🔔 开始请求 HealthKit 权限...")
            await dataManager.requestHealthKitPermission()
        }
        
        print("🔔 初始权限请求完成")
    }
}
