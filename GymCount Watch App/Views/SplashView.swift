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
    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0

    var body: some View {
        if isActive {
            ContentView()
        } else {
            VStack(spacing: 10) {
                // Logo
                Image("AppIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                // 应用名称
                Text(NSLocalizedString("app_name", comment: "健身计数器"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(textOpacity)

                // 标语
                Text(NSLocalizedString("app_slogan", comment: "应用标语"))
                    .font(GymStyle.detail)
                    .foregroundColor(.secondary)
                    .opacity(textOpacity)
            }
            .onAppear {
                withAnimation(.spring(duration: 0.7, bounce: 0.3)) {
                    iconScale = 1.0
                    iconOpacity = 1.0
                }
                withAnimation(.easeInOut(duration: 0.5).delay(0.3)) {
                    textOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isActive = true
                        dataManager.completeFirstLaunch()
                    }
                }
            }
        }
    }
}

#Preview {
    SplashView()
        .environmentObject(DataManager.shared)
}
