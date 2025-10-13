//
//  SplashView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

struct SplashView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var isActive = false
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.0
    
    var body: some View {
        if isActive {
            ContentView()
        } else {
            VStack(spacing: 16) {
                // 应用图标
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .scaleEffect(scale)
                    .opacity(opacity)
                
                // 应用名称
                Text(NSLocalizedString("app_name", comment: "健身计数器"))
                    .font(.headline)
                    .fontWeight(.bold)
                    .opacity(opacity)
                
                // 标语
                Text(NSLocalizedString("app_slogan", comment: "应用标语"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(opacity)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0)) {
                    scale = 1.0
                    opacity = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isActive = true
                        // 标记首次启动完成
                        dataManager.completeFirstLaunch()
                    }
                }
            }
        }
    }
}

#Preview {
    SplashView()
}
