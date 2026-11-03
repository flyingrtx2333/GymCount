import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import UIKit

struct RecordDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    var sourceURL: URL?
    var preferredFilename: String?
    init(data: Data) { self.data = data }
    init(url: URL, filename: String) { data = Data(); sourceURL = url; preferredFilename = filename }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw RecordFileError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let sourceURL {
            // Keep the exported name independent of the staging file's original filename.
            let wrapper = FileWrapper(regularFileWithContents: try Data(contentsOf: sourceURL, options: .mappedIfSafe))
            wrapper.preferredFilename = preferredFilename
            return wrapper
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct RecordSettingsView: View {
    private enum ExportIntent: Equatable { case trainingBackup, other }
    @EnvironmentObject private var store: PhoneWorkoutStore
    @EnvironmentObject private var trainingReminder: PhoneTrainingReminder
    @Environment(\.openURL) private var openURL
    @AppStorage("records.appearance") private var appearance = RecordAppearance.system.rawValue
    @AppStorage("records.last-backup-success") private var lastBackupSuccess: Double = 0
    let records: [PhoneTrainingSession]
    let filter: RecordFilter
    @State private var importing = false
    @State private var exporting = false
    @State private var document: RecordDocument?
    @State private var contentType = UTType.json
    @State private var filename = "PowerReps-Records"
    @State private var exportIntent: ExportIntent?
    @State private var preview: RecordRestorePreview?
    @State private var message: String?
    @State private var busy = false
    private var hasExportableSets: Bool {
        records.contains { record in
            record.sets.contains { filter.exercise == nil || $0.exercise == filter.exercise }
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            RecordPageHeader(title: String(localized: "设置"), identifier: "settings-heading") { EmptyView() }
            List {
                Section {
                    Picker(String(localized: "外观"), selection: $appearance) {
                        ForEach(RecordAppearance.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.menu)
                }.recordSectionStyle()
                Section {
                    Toggle(isOn: Binding(get: { trainingReminder.enabled }, set: { value in
                        Task { await trainingReminder.setEnabled(value, dates: store.trainingDates) }
                    })) {
                        Label {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text(String(localized: "未训练提醒")).fixedSize()
                                    Spacer(minLength: 8)
                                    Text("20:00").font(Studio.Fonts.caption).foregroundStyle(Studio.muted).monospacedDigit().fixedSize()
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "未训练提醒"))
                                    Text("20:00").font(Studio.Fonts.caption).foregroundStyle(Studio.muted).monospacedDigit()
                                }
                            }
                        } icon: { Image(systemName: "bell") }
                    }.disabled(trainingReminder.updating)
                        .accessibilityIdentifier("training-reminder-toggle")
                    if trainingReminder.enabled, let error = trainingReminder.error {
                        HStack(alignment: .firstTextBaseline) {
                            Text(error).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                            Spacer(minLength: 8)
                            if trainingReminder.authorized {
                                Button(String(localized: "重试")) {
                                    Task { await trainingReminder.refresh(dates: store.trainingDates) }
                                }
                            } else {
                                Button(String(localized: "允许通知")) {
                                    Task {
                                        let settings = await UNUserNotificationCenter.current().notificationSettings()
                                        if settings.authorizationStatus == .denied {
                                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                        } else { await trainingReminder.refresh(dates: store.trainingDates, requestPermission: true) }
                                    }
                                }
                            }
                        }.disabled(trainingReminder.updating)
                            .accessibilityIdentifier("training-reminder-status")
                    }
                }.recordSectionStyle()
                #if GYMCOUNT_SYNC
                Section { NavigationLink { RecordSyncView().toolbar(.visible, for: .navigationBar) } label: { Label(String(localized: "手表同步"), systemImage: "applewatch") } }.recordSectionStyle()
                #endif
                Section {
                    Button { exportBackup() } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "训练记录备份"))
                                if lastBackupSuccess.isFinite && lastBackupSuccess > 0 {
                                    Text(String(localized: "上次备份：\(Date(timeIntervalSince1970: lastBackupSuccess).formatted(date: .abbreviated, time: .shortened))"))
                                        .font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("records-backup-last-success")
                                }
                            }.padding(.vertical, 4)
                        } icon: { Image(systemName: "externaldrive.badge.plus") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("records-backup")
                        .disabled(store.requiresRecovery)
                    Button { importing = true } label: { Label(String(localized: "恢复备份"), systemImage: "arrow.down.doc") }
                        .accessibilityIdentifier("records-restore")
                    Menu {
                        Button(String(localized: "训练汇总 CSV")) { exportCSV(sets: false) }
                        Button(String(localized: "组明细 CSV")) { exportCSV(sets: true) }
                            .disabled(!hasExportableSets)
                            .accessibilityIdentifier("records-export-sets")
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "导出当前筛选记录"))
                                Text((filter.exercise?.recordName ?? String(localized: "全部动作")) + " · " + filter.rangeTitle + " · " + String(localized: "\(records.count) 条记录"))
                                    .font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("records-export-scope")
                            }.padding(.vertical, 4)
                        } icon: { Image(systemName: "square.and.arrow.up") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                        .disabled(records.isEmpty)
                        .accessibilityIdentifier("records-export")
                    if FileManager.default.fileExists(atPath: store.snapshotURL.deletingLastPathComponent().appendingPathComponent("before-restore.json").path) {
                        Button(String(localized: "导出恢复前快照")) { exportBeforeRestore() }
                    }
                } header: { RecordSectionTitle(String(localized: "数据")) }
                    .recordSectionStyle().disabled(busy)
                if let draft = store.session {
                    Section {
                        if !draft.sets.isEmpty || draft.reps > 0 { Button(String(localized: "保存已有草稿"), action: store.finish) }
                        else { Button(String(localized: "清除空草稿"), action: store.cancelEmptyTraining) }
                    } header: { RecordSectionTitle(String(localized: "未归档的手机记录")) }
                        .recordSectionStyle()
                }
                Section {
                    NavigationLink(String(localized: "使用帮助")) { RecordHelpView().toolbar(.visible, for: .navigationBar) }
                    #if GYMCOUNT_SYNC
                    NavigationLink(String(localized: "手表健康权限")) {
                        List { Section {
                            Text(String(localized: "在手表本机操作")).font(Studio.Fonts.section)
                            Text(String(localized: "设置 → 健康 → 数据来源、App 和服务 → 健身计数器"))
                            Text(String(localized: "开启「允许写入」中的「体能训练」。"))
                        }.recordSectionStyle() }
                            .listStyle(.plain).recordListStyle().font(Studio.Fonts.body).recordCanvasSpacing()
                            .navigationTitle(String(localized: "手表健康权限")).navigationBarTitleDisplayMode(.inline)
                            .toolbar(.visible, for: .navigationBar)
                    }
                    #endif
                } header: { RecordSectionTitle(String(localized: "帮助")) }
                    .recordSectionStyle()
                #if DEBUG && GYMCOUNT_SYNC
                Section {
                    NavigationLink(String(localized: "开发者工具")) { PhoneDeveloperToolsView().toolbar(.visible, for: .navigationBar) }
                } header: { RecordSectionTitle(String(localized: "高级")) }
                    .recordSectionStyle()
                #endif
                Section {
                    LabeledContent(String(localized: "版本"), value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—") + ")")
                }.recordSectionStyle()
                if let error = store.storageError { Text(error).font(Studio.Fonts.caption).foregroundStyle(.red) }
            }.listStyle(.plain).recordListStyle().font(Studio.Fonts.body)
                .environment(\.defaultMinListRowHeight, Studio.controlHeight)
                .contentMargins(.top, 8, for: .scrollContent)
            }.recordCanvasSpacing().background(Studio.background)
                .navigationTitle(String(localized: "设置")).navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        }
        .fileExporter(isPresented: $exporting, document: document, contentTypes: [contentType], defaultFilename: filename, onCompletion: { result in
            let intent = exportIntent
            clearExport()
            switch result {
            case .success:
                if intent == .trainingBackup { lastBackupSuccess = Date().timeIntervalSince1970 }
            case .failure(let error):
                message = error.localizedDescription
            }
        }, onCancellation: {
            clearExport()
        })
        .overlay { if busy { ProgressView().padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard !busy else { return }
            busy = true
            Task { @MainActor in
                defer { busy = false }
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    preview = try await store.readBackup(url)
                } catch { message = error.localizedDescription }
            }
        }
        .sheet(item: $preview) { value in
            NavigationStack {
                Form {
                    Section {
                        LabeledContent(String(localized: "备份日期"), value: value.backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent(String(localized: "新增记录"), value: "\(value.added)")
                        LabeledContent(String(localized: "保留现有记录"), value: "\(value.skipped)")
                        if value.drafts > 0 {
                            LabeledContent(String(localized: "新增草稿"), value: "\(value.drafts)")
                        }
                        if store.requiresRecovery {
                            Text(String(localized: "原记录文件会保留，恢复后使用此备份。"))
                                .font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                        }
                    }.listRowBackground(Studio.surface)
                }.recordListStyle().navigationTitle(String(localized: "恢复备份")).navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack(spacing: 12) {
                            if busy { ProgressView() }
                            Spacer(minLength: 0)
                            Button(store.requiresRecovery ? String(localized: "恢复本地记录") : String(localized: "合并恢复")) {
                                guard !busy else { return }
                                busy = true
                                Task { @MainActor in
                                    defer { busy = false }
                                    do { try await store.mergeBackup(value); preview = nil; message = String(localized: "恢复完成") }
                                    catch { preview = nil; message = error.localizedDescription }
                                }
                            }.buttonStyle(StudioPrimaryButton()).disabled(busy).accessibilityIdentifier("confirm-restore")
                        }
                        .padding(.horizontal, Studio.inset).padding(.vertical, 12)
                        .background(Studio.background)
                        .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: Studio.hairline) }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { preview = nil }.disabled(busy) } }
            }.tint(Studio.accent).presentationDetents([.medium, .large]).interactiveDismissDisabled(busy)
        }
        .alert(String(localized: "数据管理"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(String(localized: "确定"), role: .cancel) {}
        } message: { Text(message ?? "") }
    }
    private func clearExport() {
        if let url = document?.sourceURL { try? FileManager.default.removeItem(at: url) }
        exportIntent = nil; document = nil; exporting = false
    }
    private func exportBackup() {
        guard !busy, exportIntent == nil else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { present(try await store.exportBackup(), name: "PowerReps-Records", intent: .trainingBackup) }
            catch { message = error.localizedDescription }
        }
    }
    private func exportBeforeRestore() {
        guard !busy, exportIntent == nil else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { present(try await store.exportBeforeRestore(), name: "PowerReps-BeforeRestore", intent: .other) }
            catch { message = error.localizedDescription }
        }
    }
    private func present(_ url: URL, name: String, intent: ExportIntent) {
        filename = name + "-" + Date().ISO8601Format().prefix(10)
        exportIntent = intent; document = RecordDocument(url: url, filename: filename + ".json"); contentType = .json
        exporting = true
    }
    private func exportCSV(sets: Bool) {
        guard !records.isEmpty, !sets || hasExportableSets else { return }
        present(Data(store.csv(records: records, sets: sets, exercise: filter.exercise).utf8), type: .commaSeparatedText, name: sets ? "PowerReps-Sets" : "PowerReps-Workouts")
    }
    private func present(_ data: Data, type: UTType, name: String, intent: ExportIntent = .other) {
        guard exportIntent == nil else { return }
        exportIntent = intent
        document = RecordDocument(data: data); contentType = type
        filename = name + "-" + Date().ISO8601Format().prefix(10); exporting = true
    }
}

private struct RecordHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Studio.spacing) {
                helpSection(String(localized: "训练记录"), text: String(localized: "在记录页补记训练；左滑记录可编辑或删除。"))
                helpSection(String(localized: "备份与恢复"), text: String(localized: "在设置中导出训练记录备份。恢复前可预览新增记录，已有记录保留手机当前内容。"))
                #if GYMCOUNT_SYNC
                VStack(alignment: .leading, spacing: 8) {
                    helpSection(String(localized: "手表同步"), text: String(localized: "在手表结束并保存训练后，打开手机记录页同步。"))
                    NavigationLink {
                        RecordSyncView()
                    } label: {
                        HStack {
                            Text(String(localized: "同步状态与重试"))
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right").font(Studio.Fonts.caption.weight(.semibold))
                        }.frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
                    }.buttonStyle(RecordPressStyle())
                }
                #endif
            }.padding(Studio.inset).frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.recordCanvasSpacing().background(Studio.background).foregroundStyle(Studio.ink)
            .navigationTitle(String(localized: "使用帮助")).navigationBarTitleDisplayMode(.inline)
    }
    private func helpSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Studio.Fonts.section)
            Text(text).font(Studio.Fonts.body).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if GYMCOUNT_SYNC
struct RecordSyncView: View {
    @EnvironmentObject private var capture: PhoneCaptureStore
    @EnvironmentObject private var store: PhoneWorkoutStore
    var body: some View {
        List {
            if capture.watchSetupState != .ready {
                Section {
                    Label(String(localized: "自动计数需要 Apple Watch"), systemImage: "applewatch")
                        .font(Studio.Fonts.section)
                        .accessibilityIdentifier("watch-setup-heading")
                    switch capture.watchSetupState {
                    case .unpaired:
                        Text(String(localized: "打开 iPhone 的 Watch App，按提示配对手表。"))
                            .font(Studio.Fonts.body).fixedSize(horizontal: false, vertical: true)
                        Link(String(localized: "查看配对指南"), destination: URL(string: "https://support.apple.com/guide/watch/apdde4d6f98e/watchos")!)
                    case .notInstalled:
                        installationSteps
                        installationLink
                    case .checking:
                        Text(String(localized: "在 iPhone 的 Watch App 中完成配对，并安装手表应用。"))
                            .font(Studio.Fonts.body).fixedSize(horizontal: false, vertical: true)
                        installationLink
                    case .ready: EmptyView()
                    }
                }.recordSectionStyle()
            }
            Section {
                Label(capture.workoutSyncState.title, systemImage: capture.workoutSyncState.symbol)
                    .foregroundStyle(capture.workoutSyncState == .failed ? Color.red : Studio.ink)
                if let last = store.lastSyncAt {
                    LabeledContent(String(localized: "最后同步"), value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if capture.workoutSyncState == .failed, !capture.workoutSyncMessage.isEmpty {
                    Text(capture.workoutSyncMessage).font(Studio.Fonts.caption).foregroundStyle(.red)
                }
                Button(String(localized: "立即同步")) { capture.requestWorkoutHistory(force: true) }
                    .disabled(capture.workoutSyncState == .receiving || capture.workoutSyncState == .connecting)
                    .accessibilityIdentifier("sync-now")
            }.recordSectionStyle()
        }.listStyle(.plain).recordListStyle().font(Studio.Fonts.body).recordCanvasSpacing()
            .navigationTitle(String(localized: "手表同步")).navigationBarTitleDisplayMode(.inline)
    }

    private var installationSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "打开 iPhone 的 Watch App。"))
            Text(String(localized: "我的手表 → 可用 App。"))
            Text(String(localized: "找到「健身计数器」，点击「安装」。"))
        }.font(Studio.Fonts.body).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("watch-install-steps")
    }
    private var installationLink: some View {
        Link(String(localized: "查看安装指南"), destination: URL(string: "https://support.apple.com/109023")!)
    }
}
#endif
