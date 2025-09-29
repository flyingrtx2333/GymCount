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
    
    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(dataManager)
        }
    }
}
