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
    
    init() {
        // 注册快捷指令
        GymCountShortcutsProvider.updateAppShortcutParameters()
    }
    
    var body: some Scene {
        WindowGroup {
            if dataManager.isFirstLaunch {
                SplashView()
                    .environmentObject(dataManager)
            } else {
                ContentView()
                    .environmentObject(dataManager)
            }
        }
    }
}
