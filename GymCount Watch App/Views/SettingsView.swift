//
//  SettingsView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import HealthKit

enum WatchHealthPermissionGuide {
    static let path = String(localized: "设置 → 健康 → 数据来源、App 和服务 → 健身计数器")
    static let instruction = String(localized: "开启「允许写入」中的「体能训练」。")
    static let alternateName = String(localized: "应用也可能显示为 PowerReps。")
    static let message = String(localized: "在手表本机打开：\n") + path + "\n" + instruction + "\n" + alternateName
}

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var notificationManager: NotificationManager
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @State private var tempSettings: AppSettings
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var healthKitStatus: HKAuthorizationStatus = .notDetermined
    @State private var showingHealthGuide = false
    @State private var showingNotificationGuide = false
    @State private var showingReminderError = false
    @State private var saving = false

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--"
    }
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--"
    }

    init() {
        _tempSettings = State(initialValue: DataManager.shared.settings)
        _reminderEnabled = State(initialValue: NotificationManager.shared.dailyReminderEnabled)
        _reminderTime = State(initialValue: NotificationManager.shared.dailyReminderTime)
    }

    private var hasChanges: Bool {
        tempSettings != dataManager.settings || reminderEnabled != notificationManager.dailyReminderEnabled ||
        Calendar.current.dateComponents([.hour, .minute], from: reminderTime) !=
        Calendar.current.dateComponents([.hour, .minute], from: notificationManager.dailyReminderTime)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: GymStyle.spacing) {
                // MARK: 器械重量
                Section {
                    WeightRow(
                        label: NSLocalizedString("equipment weight", comment: "器械重量"),
                        value: $tempSettings.defaultWeight,
                        step: 2.5,
                        minValue: 0
                    )
                }

                // MARK: 我的体重
                Section {
                    WeightRow(
                        label: NSLocalizedString("my_weight", comment: "我的体重"),
                        value: $tempSettings.userBodyWeight,
                        step: 1.0,
                        minValue: 30,
                        maxValue: 200
                    )
                }

                // MARK: 运动圆环
                Section(header: sectionTitle(String(localized: "运动圆环"))) {
                    // 同步开关
                    Toggle(String(localized: "同步训练"), isOn: $tempSettings.healthKitSyncEnabled)
                        .font(GymStyle.body)
                        .toggleStyle(.switch)
                        .frame(minHeight: 44)
                        .accessibilityLabel(NSLocalizedString("sync_to_activity_rings", comment: "同步到运动圆环"))

                    if tempSettings.healthKitSyncEnabled {
                        // 自动同步
                        Toggle(NSLocalizedString("auto_sync", comment: "自动同步"), isOn: $tempSettings.autoSyncToHealthKit)
                            .font(GymStyle.body)
                            .toggleStyle(.switch)
                            .frame(minHeight: 44)

                        // 权限状态
                        StatusRow(
                            icon: healthKitStatusIcon,
                            iconColor: healthKitStatusColor,
                            label: NSLocalizedString("permission_status", comment: "权限状态"),
                            value: healthKitStatusText
                        )

                        // 立即同步
                        Button(action: {
                            Task { await dataManager.syncAllWorkoutsToHealthKit(enabled: tempSettings.healthKitSyncEnabled) }
                        }) {
                            Label(
                                NSLocalizedString("sync_all_records", comment: "立即同步所有记录"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(GymStyle.body)
                            .foregroundStyle(GymStyle.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(healthKitManager.isSyncing || dataManager.workoutHistory.isEmpty)
                        if let message = healthKitManager.syncMessage {
                            Text(message).font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("settings.healthSyncResult")
                        }

                        // 请求权限
                        if healthKitStatus == .notDetermined {
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
                                .foregroundStyle(GymStyle.accent)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { showingHealthGuide = true } label: {
                        Label(String(localized: "健康权限怎么开"), systemImage: "questionmark.circle")
                            .font(GymStyle.body)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain).foregroundStyle(GymStyle.accent)
                    .accessibilityIdentifier("settings.healthGuide")
                }

                // MARK: 通知
                Section(header: sectionTitle(NSLocalizedString("notification_section", comment: "通知设置"))) {
                    StatusRow(
                        icon: notificationStatusIcon,
                        iconColor: notificationStatusColor,
                        label: NSLocalizedString("notification_permission", comment: "通知权限"),
                        value: notificationStatusText
                    )

                    Toggle(String(localized: "每日提醒"), isOn: $reminderEnabled)
                        .font(GymStyle.body)
                        .toggleStyle(.switch)
                        .frame(minHeight: 44)
                    if reminderEnabled {
                        DatePicker(String(localized: "提醒时间"), selection: $reminderTime, displayedComponents: .hourAndMinute)
                        if let error = notificationManager.reminderError {
                            Text(error).font(GymStyle.detail).foregroundStyle(.orange)
                        }
                    }
                    if notificationManager.authorizationStatus == .denied {
                        Button(String(localized: "通知权限怎么开")) { showingNotificationGuide = true }
                            .font(GymStyle.body).foregroundStyle(GymStyle.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).buttonStyle(.plain)
                    } else if !notificationManager.isAuthorized {
                        Button(action: {
                            Task { await notificationManager.requestNotificationPermission() }
                        }) {
                            Label(
                                NSLocalizedString("request_notification_permission", comment: "请求通知权限"),
                                systemImage: "bell.badge"
                            )
                            .font(GymStyle.body)
                            .foregroundStyle(GymStyle.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }

                #if DEBUG
                NavigationLink { WatchAdvancedSettingsView() } label: {
                    Label(String(localized: "高级"), systemImage: "gearshape.2")
                        .font(GymStyle.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("settings.advanced")
                #endif

                NavigationLink { HelpView() } label: {
                    Label(NSLocalizedString("help_title", comment: "使用帮助"), systemImage: "questionmark.circle")
                        .font(GymStyle.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("settings.help")

                // MARK: 应用信息
                Section {
                    HStack {
                        Text(NSLocalizedString("version", comment: "版本"))
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                    }
                    .font(GymStyle.detail).foregroundStyle(GymStyle.muted).padding(.vertical, 6)
                    .accessibilityIdentifier("settings.version")
                }
            }
            .gymPageContent()
            }
            .navigationBarBackButtonHidden(true)
            .gymPage()
            .gymNavigationTitle(String(localized: "设置"), back: { presentationMode.wrappedValue.dismiss() })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasChanges {
                    Button(String(localized: "保存")) {
                        saving = true
                        Task { @MainActor in
                            let reminderChanged = reminderEnabled != notificationManager.dailyReminderEnabled ||
                                Calendar.current.dateComponents([.hour, .minute], from: reminderTime) !=
                                Calendar.current.dateComponents([.hour, .minute], from: notificationManager.dailyReminderTime)
                            if reminderChanged {
                                guard await notificationManager.updateDailyReminder(enabled: reminderEnabled, time: reminderTime) else {
                                    showingReminderError = true
                                    saving = false
                                    return
                                }
                            }
                            dataManager.updateSettings(tempSettings)
                            presentationMode.wrappedValue.dismiss()
                            saving = false
                        }
                    }
                    .buttonStyle(GymActionStyle(primary: true))
                    .disabled(saving)
                    .accessibilityIdentifier("settings.save")
                    .padding(.horizontal, GymStyle.inset)
                    .padding(.bottom, 4)
                    .background(Color.black)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)

        }
        .onAppear {
            healthKitStatus = dataManager.getHealthKitAuthorizationStatus()
            notificationManager.checkAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                healthKitManager.refreshAuthorizationStatus()
                healthKitStatus = healthKitManager.authorizationStatus
                notificationManager.checkAuthorizationStatus()
                notificationManager.scheduleDailyReminder()
            }
        }
        .alert(String(localized: "通知权限"), isPresented: $showingNotificationGuide) {
            Button(String(localized: "完成"), role: .cancel) {}
        } message: {
            Text(String(localized: "在 iPhone 的 Watch App → 通知中，允许健身计数器通知。更改后回到这里。"))
        }
        .alert(String(localized: "每日提醒"), isPresented: $showingReminderError) {
            Button(String(localized: "完成"), role: .cancel) {}
        } message: {
            Text(notificationManager.reminderError ?? String(localized: "提醒未能保存，请重试"))
        }
        .sheet(isPresented: $showingHealthGuide) {
            NavigationStack {
                ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "在手表本机操作")).font(GymStyle.body.bold())
                    Text(WatchHealthPermissionGuide.path)
                    Text(WatchHealthPermissionGuide.instruction)
                    Text(WatchHealthPermissionGuide.alternateName).font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                    Text(String(localized: "开启后，回到设置点「立即同步所有记录」。")).font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                }
                .padding(.horizontal, GymStyle.inset)
                .padding(.bottom, 12)
                }
            .gymPage().gymNavigationTitle(String(localized: "健康权限"), back: { showingHealthGuide = false })
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(GymStyle.caption).foregroundStyle(GymStyle.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
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
        case .provisional: return NSLocalizedString("provisional", comment: "临时授权")
        default: return NSLocalizedString("not_determined", comment: "未确定")
        }
    }
}

// MARK: - 重量调节行（合并式）

struct WeightRow: View {
    let label: String
    @Binding var value: Double
    let step: Double
    var minValue: Double = 0
    var maxValue: Double = .infinity

    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 4) {
                Text(label).font(GymStyle.body)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Text(formatValue(value) + String(localized: " 公斤"))
                    .font(GymStyle.caption).foregroundStyle(GymStyle.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .monospacedDigit().fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.right")
                    .font(GymStyle.detail).foregroundStyle(GymStyle.muted)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(GymStyle.line).frame(height: 0.5).accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            WeightInputView(title: label, value: value, minimum: minValue, maximum: maxValue, step: step) {
                value = $0
            }
        }
    }

    private func formatValue(_ v: Double) -> String {
        v.formatted(.number.grouping(.never).precision(.significantDigits(1...15)))
    }
}

// MARK: - 状态显示行

struct StatusRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        Label(value, systemImage: icon)
            .font(GymStyle.caption).foregroundStyle(iconColor)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue(value)
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataManager.shared)
        .environmentObject(NotificationManager.shared)
}

#if DEBUG
private struct WatchAdvancedSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            NavigationLink { CollectionView() } label: {
                Label(String(localized: "采集测试"), systemImage: "waveform.path")
            }.accessibilityIdentifier("settings.capture")
        }
        .gymPage()
        .gymNavigationTitle(String(localized: "高级"), back: { dismiss() })
    }
}
#endif
