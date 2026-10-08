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
    @State private var healthKitStatus: HKAuthorizationStatus = .notDetermined
    @State private var siriStatus: INSiriAuthorizationStatus = .notDetermined

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--"
    }
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--"
    }

    init() {
        _tempSettings = State(initialValue: DataManager.shared.settings)
    }

    var body: some View {
        NavigationView {
            List {
                #if DEBUG || GYMCOUNT_CAPTURE
                Section {
                    NavigationLink { CollectionView() } label: {
                        Label("采集测试", systemImage: "waveform.path")
                            .font(GymStyle.body)
                    }
                }
                #endif


                // MARK: 器械重量
                Section {
                    WeightRow(
                        label: NSLocalizedString("equipment weight", comment: "器械重量"),
                        icon: "dumbbell.fill",
                        iconColor: .blue,
                        value: $tempSettings.defaultWeight,
                        step: 2.5,
                        minValue: 0
                    )
                }

                // MARK: 我的体重
                Section {
                    WeightRow(
                        label: NSLocalizedString("my_weight", comment: "我的体重"),
                        icon: "person.fill",
                        iconColor: .green,
                        value: $tempSettings.userBodyWeight,
                        step: 1.0,
                        minValue: 30,
                        maxValue: 200
                    )
                }

                // MARK: 运动圆环
                Section(header: Text(NSLocalizedString("healthkit_section", comment: "Apple Watch 运动圆环"))) {
                    // 同步开关
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .frame(width: 16)
                        Text(NSLocalizedString("sync_to_activity_rings", comment: "同步到运动圆环"))
                            .font(GymStyle.body)
                        Spacer()
                        Toggle("", isOn: $tempSettings.healthKitSyncEnabled)
                            .labelsHidden()
                    }

                    if tempSettings.healthKitSyncEnabled {
                        // 自动同步
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.blue)
                                .frame(width: 16)
                            Text(NSLocalizedString("auto_sync", comment: "自动同步"))
                                .font(GymStyle.body)
                            Spacer()
                            Toggle("", isOn: $tempSettings.autoSyncToHealthKit)
                                .labelsHidden()
                        }

                        // 权限状态
                        StatusRow(
                            icon: healthKitStatusIcon,
                            iconColor: healthKitStatusColor,
                            label: NSLocalizedString("permission_status", comment: "权限状态"),
                            value: healthKitStatusText
                        )

                        // 立即同步
                        Button(action: {
                            Task { await dataManager.syncAllWorkoutsToHealthKit() }
                        }) {
                            Label(
                                NSLocalizedString("sync_all_records", comment: "立即同步所有记录"),
                                systemImage: "icloud.and.arrow.up"
                            )
                            .font(GymStyle.body)
                            .foregroundColor(.blue)
                        }

                        // 请求权限
                        if healthKitStatus.rawValue != 2 {
                            Button(action: {
                                Task {
                                    await dataManager.requestHealthKitPermission()
                                    healthKitStatus = dataManager.getHealthKitAuthorizationStatus()
                                }
                            }) {
                                Label(
                                    NSLocalizedString("request_healthkit_permission", comment: "请求 HealthKit 权限"),
                                    systemImage: "lock.open"
                                )
                                .font(GymStyle.body)
                                .foregroundColor(.orange)
                            }
                        }
                    }
                }

                // MARK: 通知
                Section(header: Text(NSLocalizedString("notification_section", comment: "通知设置"))) {
                    StatusRow(
                        icon: notificationStatusIcon,
                        iconColor: notificationStatusColor,
                        label: NSLocalizedString("notification_permission", comment: "通知权限"),
                        value: notificationStatusText
                    )

                    if notificationManager.authorizationStatus != .authorized {
                        Button(action: {
                            Task { await notificationManager.requestNotificationPermission() }
                        }) {
                            Label(
                                NSLocalizedString("request_notification_permission", comment: "请求通知权限"),
                                systemImage: "bell.badge"
                            )
                            .font(GymStyle.body)
                            .foregroundColor(.blue)
                        }
                    }
                }

                // MARK: 应用信息
                Section(header: Text(NSLocalizedString("app_info", comment: "应用信息"))) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        Text(NSLocalizedString("version", comment: "版本"))
                            .font(GymStyle.body)
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .font(GymStyle.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .font(GymStyle.body)
            .navigationTitle(NSLocalizedString("settings", comment: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "保存")) {
                        dataManager.updateSettings(tempSettings)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(GymStyle.button)
                }
            }
        }
        .onAppear {
            healthKitStatus = dataManager.getHealthKitAuthorizationStatus()
            notificationManager.checkAuthorizationStatus()
        }
    }

    // MARK: - HealthKit 状态

    private var healthKitStatusIcon: String {
        switch healthKitStatus.rawValue {
        case 2: return "checkmark.circle.fill"
        case 1: return "xmark.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }
    private var healthKitStatusColor: Color {
        switch healthKitStatus.rawValue {
        case 2: return .green
        case 1: return .red
        default: return .orange
        }
    }
    private var healthKitStatusText: String {
        switch healthKitStatus.rawValue {
        case 2: return NSLocalizedString("authorized", comment: "已授权")
        case 1: return NSLocalizedString("denied", comment: "已拒绝")
        default: return NSLocalizedString("not_determined", comment: "未确定")
        }
    }

    // MARK: - 通知状态

    private var notificationStatusIcon: String {
        switch notificationManager.authorizationStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }
    private var notificationStatusColor: Color {
        switch notificationManager.authorizationStatus {
        case .authorized: return .green
        case .denied: return .red
        default: return .orange
        }
    }
    private var notificationStatusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized: return NSLocalizedString("authorized", comment: "已授权")
        case .denied: return NSLocalizedString("denied", comment: "已拒绝")
        case .provisional, .ephemeral: return NSLocalizedString("provisional", comment: "临时授权")
        default: return NSLocalizedString("not_determined", comment: "未确定")
        }
    }
}

// MARK: - 重量调节行（合并式）

struct WeightRow: View {
    let label: String
    let icon: String
    let iconColor: Color
    @Binding var value: Double
    let step: Double
    var minValue: Double = 0
    var maxValue: Double = .infinity

    var body: some View {
        VStack(spacing: 6) {
            // 标签 + 当前值
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 16)
                Text(label)
                    .font(GymStyle.body)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(formatValue(value))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.2), value: value)
                    Text("kg")
                        .font(GymStyle.detail)
                        .foregroundColor(.secondary)
                }
            }
            // 加减控制
            HStack(spacing: 8) {
                Button(action: { if value - step >= minValue { value -= step } }) {
                    Image(systemName: "minus")
                        .font(GymStyle.button)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.orange.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .disabled(value - step < minValue)

                Button(action: { if value + step <= maxValue { value += step } }) {
                    Image(systemName: "plus")
                        .font(GymStyle.button)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.blue.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .disabled(value + step > maxValue)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

// MARK: - 状态显示行

struct StatusRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 16)
            Text(label)
                .font(GymStyle.body)
            Spacer()
            Text(value)
                .font(GymStyle.body)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataManager.shared)
        .environmentObject(NotificationManager.shared)
}
