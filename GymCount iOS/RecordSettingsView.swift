import SwiftUI
import UniformTypeIdentifiers

struct RecordDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw RecordFileError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct RecordSettingsView: View {
    private enum ExportIntent: Equatable { case trainingBackup, other }
    @EnvironmentObject private var store: PhoneWorkoutStore
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
            Form {
                Section {
                    Picker(String(localized: "外观"), selection: $appearance) {
                        ForEach(RecordAppearance.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                }.listRowBackground(Studio.surface)
                #if GYMCOUNT_SYNC
                Section { NavigationLink { RecordSyncView() } label: { Label(String(localized: "手表同步"), systemImage: "applewatch") } }.listRowBackground(Studio.surface)
                #endif
                Section(String(localized: "数据")) {
                    Button { exportBackup() } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "训练记录备份"))
                                if lastBackupSuccess.isFinite && lastBackupSuccess > 0 {
                                    Text(String(localized: "上次备份：\(Date(timeIntervalSince1970: lastBackupSuccess).formatted(date: .abbreviated, time: .shortened))"))
                                        .font(.caption).foregroundStyle(Studio.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("records-backup-last-success")
                                }
                            }.padding(.vertical, 4)
                        } icon: { Image(systemName: "externaldrive.badge.plus") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("records-backup")
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
                                    .font(.caption).foregroundStyle(Studio.muted)
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
                }.listRowBackground(Studio.surface).disabled(busy)
                if let draft = store.session {
                    Section(String(localized: "未归档的手机记录")) {
                        if !draft.sets.isEmpty || draft.reps > 0 { Button(String(localized: "保存已有草稿"), action: store.finish) }
                        else { Button(String(localized: "清除空草稿"), action: store.cancelEmptyTraining) }
                    }.listRowBackground(Studio.surface)
                }
                Section(String(localized: "帮助")) {
                    NavigationLink(String(localized: "手表健康权限")) {
                        List {
                            Text(String(localized: "设置 → 健康 → 数据来源、App 和服务 → 健身计数器"))
                            Text(String(localized: "开启「允许写入」中的「体能训练」。"))
                        }.recordListStyle().navigationTitle(String(localized: "手表健康权限")).navigationBarTitleDisplayMode(.inline)
                    }
                    #if GYMCOUNT_SYNC
                    NavigationLink(String(localized: "开发者工具")) { PhoneDeveloperToolsView() }
                    #endif
                }.listRowBackground(Studio.surface)
                Section {
                    LabeledContent(String(localized: "版本"), value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—") + ")")
                }.listRowBackground(Studio.surface)
                if let error = store.storageError { Text(error).font(.footnote).foregroundStyle(.red) }
            }.recordListStyle().navigationTitle(String(localized: "设置")).navigationBarTitleDisplayMode(.large)
                .toolbar(.hidden, for: .tabBar)
        }
        .fileExporter(isPresented: $exporting, document: document, contentTypes: [contentType], defaultFilename: filename, onCompletion: { result in
            let intent = exportIntent
            exportIntent = nil; document = nil; exporting = false
            switch result {
            case .success:
                if intent == .trainingBackup { lastBackupSuccess = Date().timeIntervalSince1970 }
            case .failure(let error):
                message = error.localizedDescription
            }
        }, onCancellation: {
            exportIntent = nil; document = nil; exporting = false
        })
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? Int.max) <= 32 * 1024 * 1024 else { throw RecordFileError.invalid }
                preview = try store.previewRestore(Data(contentsOf: url))
            } catch { message = error.localizedDescription }
        }
        .sheet(item: $preview) { value in
            NavigationStack {
                Form {
                    Section {
                        LabeledContent(String(localized: "备份日期"), value: value.backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent(String(localized: "新增记录"), value: "\(value.added)")
                        LabeledContent(String(localized: "保留现有记录"), value: "\(value.skipped)")
                        LabeledContent(String(localized: "新增草稿"), value: "\(value.drafts)")
                    }.listRowBackground(Studio.surface)
                    Section {
                        Button(String(localized: "合并恢复")) {
                            guard !busy else { return }
                            busy = true
                            do { try store.restore(value); preview = nil; message = String(localized: "恢复完成") }
                            catch { preview = nil; message = error.localizedDescription }
                            busy = false
                        }.disabled(busy).accessibilityIdentifier("confirm-restore")
                    }.listRowBackground(Studio.surface)
                }.recordListStyle().navigationTitle(String(localized: "恢复备份")).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { preview = nil } } }
            }.tint(Studio.accent).presentationDetents([.medium, .large])
        }
        .alert(String(localized: "数据管理"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(String(localized: "确定"), role: .cancel) {}
        } message: { Text(message ?? "") }
    }
    private func exportBackup() {
        do { present(try store.backupData(), type: .json, name: "PowerReps-Records", intent: .trainingBackup) }
        catch { message = error.localizedDescription }
    }
    private func exportBeforeRestore() {
        do {
            let url = store.snapshotURL.deletingLastPathComponent().appendingPathComponent("before-restore.json")
            let snapshot = try JSONDecoder().decode(RecordSnapshot.self, from: Data(contentsOf: url))
            try PhoneWorkoutStore.validate(snapshot)
            present(try JSONEncoder().encode(RecordBackup(snapshot: snapshot)), type: .json, name: "PowerReps-BeforeRestore")
        } catch { message = error.localizedDescription }
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

#if GYMCOUNT_SYNC
struct RecordSyncView: View {
    @EnvironmentObject private var capture: PhoneCaptureStore
    @EnvironmentObject private var store: PhoneWorkoutStore
    var body: some View {
        List {
            Section {
                Label(capture.workoutSyncState.title, systemImage: capture.workoutSyncState.symbol)
                    .foregroundStyle(capture.workoutSyncState == .failed ? Color.red : Studio.ink)
                if let last = store.lastSyncAt {
                    LabeledContent(String(localized: "最后同步"), value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if capture.workoutSyncState == .failed, !capture.workoutSyncMessage.isEmpty {
                    Text(capture.workoutSyncMessage).font(.footnote).foregroundStyle(.red)
                }
                Button(String(localized: "立即同步")) { capture.requestWorkoutHistory(force: true) }
                    .disabled(capture.workoutSyncState == .receiving || capture.workoutSyncState == .connecting)
                    .accessibilityIdentifier("sync-now")
            }.listRowBackground(Studio.surface)
        }.recordListStyle().navigationTitle(String(localized: "手表同步")).navigationBarTitleDisplayMode(.inline)
    }
}
#endif
