//
//  SettingsView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import HealthKit
import Intents

enum WatchHealthPermissionGuide {
    static let path = "设置 → 健康 → 数据来源、App 和服务 → 健身计数器"
    static let instruction = "开启「允许写入」中的「体能训练」。"
    static let alternateName = "应用也可能显示为 PowerReps。"
    static let message = "在手表本机打开：\n" + path + "\n" + instruction + "\n" + alternateName
}

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var notificationManager: NotificationManager
    @Environment(\.presentationMode) var presentationMode
    @State private var tempSettings: AppSettings
    @State private var healthKitStatus: HKAuthorizationStatus = .notDetermined
    @State private var siriStatus: INSiriAuthorizationStatus = .notDetermined
    @State private var showingHealthGuide = false

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
        NavigationStack {
            ScrollView {
            VStack(spacing: GymStyle.spacing) {
                HStack(spacing: 0) {
                    GymHeader(title: "设置", back: { presentationMode.wrappedValue.dismiss() })
                    Button("保存") {
                        dataManager.updateSettings(tempSettings)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(GymStyle.button).foregroundStyle(GymStyle.mint)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                }
                .frame(height: 28)


                // MARK: 器械重量
                Section {
                    WeightRow(
                        label: NSLocalizedString("equipment weight", comment: "器械重量"),
                        icon: "dumbbell.fill",
                        iconColor: GymStyle.mint,
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
                        iconColor: GymStyle.mint,
                        value: $tempSettings.userBodyWeight,
                        step: 1.0,
                        minValue: 30,
                        maxValue: 200
                    )
                }

                #if DEBUG || GYMCOUNT_CAPTURE
                Section {
                    NavigationLink { CollectionView() } label: {
                        Label("采集测试", systemImage: "waveform.path")
                            .font(GymStyle.body)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(GymStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                #endif

                // MARK: 运动圆环
                Section(header: Text("运动圆环")) {
                    Button { showingHealthGuide = true } label: {
                        Label("健康权限怎么开", systemImage: "questionmark.circle")
                            .font(GymStyle.body)
                            .frame(maxWidth: .infinity, minHeight: GymStyle.buttonHeight, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GymStyle.mint)
                    .accessibilityIdentifier("settings.healthGuide")
                    // 同步开关
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(GymStyle.mint)
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
                                .foregroundStyle(GymStyle.mint)
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
                            .foregroundStyle(GymStyle.mint)
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
                                .foregroundStyle(GymStyle.mint)
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
                            .foregroundStyle(GymStyle.mint)
                        }
                    }
                }

                // MARK: 应用信息
                Section(header: Text(NSLocalizedString("app_info", comment: "应用信息"))) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(GymStyle.mint)
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
            .gymPageContent(fullWidthHeader: true)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden)
            .gymPage()

        }
        .onAppear {
            healthKitStatus = dataManager.getHealthKitAuthorizationStatus()
            notificationManager.checkAuthorizationStatus()
        }
        .sheet(isPresented: $showingHealthGuide) {
            VStack(spacing: GymStyle.spacing) {
                GymHeader(title: "健康权限")
                    .padding(.horizontal, GymStyle.inset)
                    .padding(.top, 44)
                ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("在手表本机操作").font(GymStyle.body.bold())
                    Text(WatchHealthPermissionGuide.path)
                    Text(WatchHealthPermissionGuide.instruction)
                    Text(WatchHealthPermissionGuide.alternateName).font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                    Text("开启后，回到采集页点「检查同步权限」。").font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                }
                .padding(.horizontal, GymStyle.inset)
                .padding(.bottom, 12)
                }
            }
            .gymPage()
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

    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 4) {
                Text(label).font(GymStyle.body)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(formatValue(value) + " 公斤")
                    .font(GymStyle.caption).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(GymStyle.detail).foregroundStyle(GymStyle.muted)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(GymStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            WeightAdjustmentView(label: label, value: $value, step: step,
                                 minValue: minValue, maxValue: maxValue)
        }
    }

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

struct WeightAdjustmentView: View {
    let label: String
    @Binding var value: Double
    let step: Double
    let minValue: Double
    let maxValue: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                GymHeader(title: label, back: { dismiss() })
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value.formatted(.number.precision(.fractionLength(0...1))))
                        .font(GymStyle.counter).monospacedDigit()
                    Text("公斤").font(GymStyle.body).foregroundStyle(GymStyle.muted)
                }
                HStack(spacing: 20) {
                    CircleButton(icon: "minus", color: GymStyle.mint, size: 44,
                                 disabled: value - step < minValue) { value -= step }
                        .accessibilityLabel("减少重量")
                    CircleButton(icon: "plus", color: GymStyle.mint, size: 44,
                                 disabled: value + step > maxValue) { value += step }
                        .accessibilityLabel("增加重量")
                }
                Button("完成") { dismiss() }.buttonStyle(GymActionStyle(primary: true))
            }
            .gymPageContent(fullWidthHeader: true)
        }
        .toolbar(.hidden)
        .gymPage()
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
