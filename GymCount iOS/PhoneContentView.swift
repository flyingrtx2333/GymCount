import SwiftUI

struct RecordFilter: Equatable {
    enum Period: String, CaseIterable { case week, month, quarter, all, custom
        var title: String { switch self {
            case .week: String(localized: "近7天")
            case .month: String(localized: "近30天")
            case .quarter: String(localized: "近90天")
            case .all: String(localized: "全部时间")
            case .custom: String(localized: "自定义日期")
        } }
    }
    var exercise: ExerciseType?
    var period = Period.all
    var start = Calendar.current.startOfDay(for: Date())
    var end = Date()
    func includes(_ item: PhoneTrainingSession) -> Bool {
        (exercise == nil || item.exercises.contains(exercise!)) && includes(item.startTime)
    }
    func includes(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch period {
        case .all: return true
        case .custom:
            return date >= calendar.startOfDay(for: start) && date < calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        default:
            let days = period == .week ? 6 : period == .month ? 29 : 89
            return date >= calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date()))! && date <= Date()
        }
    }
    var rangeTitle: String {
        period == .custom ? start.formatted(date: .abbreviated, time: .omitted) + " – " + end.formatted(date: .abbreviated, time: .omitted) : period.title
    }
    func reps(_ item: PhoneTrainingSession) -> Int {
        guard let exercise, !item.isSummary else { return item.totalReps }
        return item.sets.filter { $0.exercise == exercise }.reduce(0) { $0 + $1.reps }
    }
    func weight(_ item: PhoneTrainingSession) -> Double {
        guard let exercise, !item.isSummary else { return item.maxWeight }
        return item.sets.filter { $0.exercise == exercise }.map(\.weight).max() ?? 0
    }
}

struct RecordDateRequest: Identifiable {
    let id = UUID()
    let singleDay: Bool
    let start: Date
    let end: Date
}

struct RecordDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let singleDay: Bool
    let apply: (Date, Date) -> Void
    @State var start: Date
    @State var end: Date
    var body: some View {
        NavigationStack {
            Form {
                DatePicker(singleDay ? String(localized: "日期") : String(localized: "开始日期"), selection: $start, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                if !singleDay {
                    DatePicker(String(localized: "结束日期"), selection: $end, in: start...max(start, Date()), displayedComponents: .date)
                }
            }.recordListStyle()
                .navigationTitle(singleDay ? String(localized: "选择日期") : String(localized: "日期范围"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成")) { apply(start, singleDay ? start : max(start, end)); dismiss() }
                    }
                }
                .onChange(of: start) { _, value in if end < value { end = value } }
        }.tint(Studio.accent)
    }
}

struct PhoneContentView: View {
    @EnvironmentObject private var store: PhoneWorkoutStore
    #if GYMCOUNT_SYNC
    @EnvironmentObject private var capture: PhoneCaptureStore
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("records.appearance") private var appearance = RecordAppearance.system.rawValue
    @State private var tab = 1
    @State private var filter = RecordFilter()
    @State private var path: [UUID] = []
    @State private var editor: RecordEditorDraft?
    @State private var selected: Set<UUID> = []
    @State private var editMode = EditMode.inactive
    @State private var deletionIDs: Set<UUID> = []
    @State private var confirmingDelete = false
    @State private var dateRequest: RecordDateRequest?
    #if GYMCOUNT_SYNC
    @State private var showingSync = false
    #endif

    private var filtered: [PhoneTrainingSession] { store.history.filter(filter.includes) }
    private var groups: [(Date, [PhoneTrainingSession])] {
        Dictionary(grouping: filtered, by: { Calendar.current.startOfDay(for: $0.startTime) }).sorted { $0.key > $1.key }
    }
    var body: some View {
        TabView(selection: $tab) {
            history.recordPage(active: tab == 1, reduced: reduceMotion).tag(1)
            RecordTrendsView { exercise, day in
                filter.exercise = exercise; filter.period = .custom; filter.start = day; filter.end = day
                path = []; tab = 1
            }.recordPage(active: tab == 3, reduced: reduceMotion).tag(3)
            RecordSettingsView(records: filtered, filter: filter)
                .recordPage(active: tab == 2, reduced: reduceMotion).tag(2)
        }
        .toolbar(.hidden, for: .tabBar)
        .background(Studio.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabs }
        .tint(Studio.accent).foregroundStyle(Studio.ink)
        .preferredColorScheme(RecordAppearance(rawValue: appearance)?.scheme)
        .onChange(of: scenePhase) { _, phase in
            #if GYMCOUNT_SYNC
            if phase == .active { capture.requestWorkoutHistory() }
            #endif
        }
        .onChange(of: filter) { _, _ in selected.formIntersection(filtered.map(\.id)) }
        .onChange(of: store.history.map(\.id)) { _, ids in
            selected.formIntersection(ids); path.removeAll { !ids.contains($0) }
        }
        .sheet(item: $editor) { draft in RecordEditorView(initial: draft) { if draft.recordID == nil { filter = RecordFilter() } } }
        .sheet(item: $dateRequest) { request in
            RecordDateSheet(singleDay: request.singleDay, apply: { start, end in
                filter.start = start; filter.end = end; filter.period = .custom
            }, start: request.start, end: request.end)
        }
        .alert(deletionIDs.count == 1 ? String(localized: "删除这条训练记录？") : String(localized: "删除所选记录？"), isPresented: $confirmingDelete) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "删除"), role: .destructive) {
                if store.deleteRecords(ids: deletionIDs) { selected.subtract(deletionIDs); editMode = .inactive }
            }
        } message: { Text(deletionDescription) }
    }
    private var deletionDescription: String {
        let rows = store.history.filter { deletionIDs.contains($0.id) }.sorted { $0.startTime < $1.startTime }
        guard let first = rows.first, let last = rows.last else { return "" }
        if rows.count == 1 { return first.exercises.map(\.recordName).joined(separator: " · ") + " · " + first.startTime.formatted(date: .abbreviated, time: .shortened) }
        return String(localized: "\(rows.count) 条记录") + "\n" + first.startTime.formatted(date: .abbreviated, time: .omitted) + " – " + last.startTime.formatted(date: .abbreviated, time: .omitted)
    }
    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton(1, String(localized: "记录"), "list.bullet.rectangle")
            tabButton(3, String(localized: "趋势"), "chart.xyaxis.line")
            tabButton(2, String(localized: "设置"), "gearshape")
        }.padding(.horizontal, 10).padding(.top, 5).background(Studio.background)
            .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 0.5) }
    }
    private func tabButton(_ id: Int, _ title: String, _ icon: String) -> some View {
        Button { tab = id } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 21))
                if !typeSize.isAccessibilitySize { Text(title).font(.caption2) }
            }.foregroundStyle(tab == id ? Studio.accent : Studio.muted)
                .frame(maxWidth: .infinity, minHeight: 54).contentShape(Rectangle())
        }.buttonStyle(RecordPressStyle()).accessibilityLabel(title)
            .accessibilityIdentifier("tab-\(id)")
            .accessibilityAddTraits(tab == id ? [.isSelected] : [])
    }
    private var history: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                historyHeader
                if !typeSize.isAccessibilitySize { filters }
                ScrollViewReader { proxy in
                    List(selection: editMode.isEditing ? $selected : nil) {
                        if typeSize.isAccessibilitySize {
                            filters
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                                .id("record-filters")
                        }
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))) {
                            Text(String(localized: "\(filtered.count) 条记录"))
                            if !typeSize.isAccessibilitySize { Text("·") }
                            Text(String(localized: "\(filtered.reduce(0) { $0 + filter.reps($1) }) 次"))
                        }.font(.subheadline).foregroundStyle(Studio.muted)
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 6, trailing: 20))
                            .id("record-overview").accessibilityIdentifier("record-summary")
                        if !filtered.isEmpty && !editMode.isEditing {
                            RecordTimeChart(records: filtered, filter: filter) { day in
                                withAnimation(RecordMotion.animation(reduced: reduceMotion)) { proxy.scrollTo(day, anchor: .top) }
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 16, trailing: 20))
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        }
                        if let error = store.storageError {
                            Text(error).font(.footnote).foregroundStyle(.red).listRowBackground(Color.clear)
                        }
                        if !store.editorDrafts.isEmpty {
                            Section(String(localized: "草稿")) {
                                ForEach(store.editorDrafts) { draft in
                                    Button { editor = draft } label: {
                                        HStack {
                                            Image(systemName: "square.and.pencil")
                                            Text(draft.recordID == nil ? String(localized: "补记训练") : String(localized: "编辑记录"))
                                            Spacer()
                                            Text(draft.date, format: .dateTime.month().day()).foregroundStyle(Studio.muted)
                                        }.frame(minHeight: 44).contentShape(Rectangle())
                                    }.accessibilityIdentifier("resume-record-draft")
                                }
                            }.listRowBackground(Color.clear)
                        }
                        if filtered.isEmpty {
                            ContentUnavailableView {
                                Label(String(localized: "暂无记录"), systemImage: "list.bullet.rectangle")
                            } actions: {
                                if !store.history.isEmpty { Button(String(localized: "清除筛选")) { filter = RecordFilter() } }
                                Button(String(localized: "补记训练")) { openEditor() }.buttonStyle(.bordered)
                            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                        }
                        ForEach(groups, id: \.0) { day, rows in
                            Text(recordDate(day)).font(.subheadline.weight(.semibold)).foregroundStyle(Studio.ink)
                                .padding(.top, 10).padding(.bottom, 6).frame(minHeight: 36)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                                .id(day)
                            ForEach(rows) { item in
                                NavigationLink(value: item.id) { RecordRow(item: item, filter: filter) }
                                    .buttonStyle(.automatic).accessibilityIdentifier("history-record").tag(item.id)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(String(localized: "删除"), role: .destructive) { askDelete([item.id]) }
                                        Button(String(localized: "编辑")) { openEditor(item) }.tint(Studio.accent)
                                    }
                            }
                        }
                    }.listStyle(.plain).environment(\.editMode, $editMode)
                        .environment(\.defaultMinListRowHeight, 0)
                        .scrollContentBackground(.hidden).background(Studio.background)
                        .listRowSeparatorTint(Studio.line)
                        .contentMargins(.top, 0, for: .scrollContent)
                        .animation(RecordMotion.animation(reduced: reduceMotion), value: filter)
                        .onChange(of: filter) { _, _ in
                            withAnimation(RecordMotion.animation(reduced: reduceMotion)) {
                                proxy.scrollTo(typeSize.isAccessibilitySize ? "record-filters" : "record-overview", anchor: .top)
                            }
                        }
                        #if GYMCOUNT_SYNC
                        .refreshable { capture.requestWorkoutHistory(force: true) }
                        #endif
                }
            }.background(Studio.background)
                .toolbar(.hidden, for: .navigationBar, .tabBar)
                #if GYMCOUNT_SYNC
                .navigationDestination(isPresented: $showingSync) {
                    RecordSyncView().toolbar(.visible, for: .navigationBar)
                }
                #endif
                .navigationDestination(for: UUID.self) { id in
                    RecordDetailView(id: id, edit: { openEditor($0) }, delete: { askDelete([$0.id]) })
                        .toolbar(.visible, for: .navigationBar)
                }
        }
    }
    private var historyHeader: some View {
        HStack(spacing: 8) {
            Text(String(localized: "训练记录")).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize { historyActions }
            if !editMode.isEditing {
                Button { openEditor() } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(String(localized: "补记训练")).accessibilityIdentifier("add-record")
            }
        }.font(.subheadline).buttonStyle(RecordPressStyle()).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var historyActions: some View {
        if !filtered.isEmpty {
            Button(editMode.isEditing ? String(localized: "完成") : String(localized: "选择")) {
                withAnimation(RecordMotion.animation(reduced: reduceMotion)) {
                    editMode = editMode.isEditing ? .inactive : .active; selected = []
                }
            }.frame(minHeight: 44).accessibilityIdentifier("record-select")
        }
        #if GYMCOUNT_SYNC
        if !editMode.isEditing {
            Button { showingSync = true } label: {
                Image(systemName: capture.workoutSyncState.symbol).font(.system(size: 20)).frame(width: 44, height: 44)
            }.accessibilityLabel(capture.workoutSyncState.title).accessibilityIdentifier("history-sync-workouts")
        }
        #endif
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 0) {
            if typeSize.isAccessibilitySize {
                HStack(spacing: 8) { historyActions; Spacer(minLength: 0) }
                    .font(.subheadline).padding(.horizontal, 20)
            }
            if filter.period == .custom && !editMode.isEditing {
                Text(filter.rangeTitle).font(.caption).foregroundStyle(Studio.muted).padding(.horizontal, 20).padding(.top, 6)
            }
            if editMode.isEditing {
                HStack {
                    Button(String(localized: "全选")) { selected = Set(filtered.map(\.id)) }.frame(minHeight: 44)
                    Spacer()
                    Text(String(localized: "\(selected.count) 条记录")).font(.subheadline).foregroundStyle(Studio.muted)
                    Button(role: .destructive) { askDelete(selected) } label: {
                        Image(systemName: "trash").foregroundStyle(.red).frame(width: 44, height: 44)
                    }.disabled(selected.isEmpty).accessibilityLabel(String(localized: "删除所选记录"))
                }.padding(.horizontal, 20)
            } else {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                layout {
                    Menu {
                        Picker(String(localized: "动作"), selection: $filter.exercise) {
                            Text(String(localized: "全部动作")).tag(Optional<ExerciseType>.none)
                            ForEach(ExerciseType.allCases, id: \.self) { Label($0.recordName, image: $0.icon).tag(Optional($0)) }
                        }
                    } label: { RecordFilterLabel(title: filter.exercise?.recordName ?? String(localized: "全部动作"), exercise: filter.exercise).frame(maxWidth: .infinity) }
                        .accessibilityIdentifier("record-exercise-filter")
                    if !typeSize.isAccessibilitySize { Divider().frame(height: 20) }
                    Menu {
                        ForEach([RecordFilter.Period.week, .month, .all], id: \.self) { period in Button(period.title) { filter.period = period } }
                        Button(String(localized: "自定义日期")) { dateRequest = RecordDateRequest(singleDay: false, start: filter.start, end: filter.end) }
                    } label: { RecordFilterLabel(title: filter.period.title).frame(maxWidth: .infinity) }
                        .accessibilityIdentifier("record-period-filter")
                    if !typeSize.isAccessibilitySize { Divider().frame(height: 20) }
                    Button { dateRequest = RecordDateRequest(singleDay: true, start: filter.start, end: filter.end) } label: {
                        Image(systemName: "calendar").font(.system(size: 18)).frame(width: 44, height: 44)
                    }.accessibilityLabel(String(localized: "选择日期"))
                }.padding(.horizontal, 12)
            }
        }.buttonStyle(RecordPressStyle()).padding(.vertical, 5).background(Studio.background)
            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: 0.5) }
    }
    private func askDelete(_ ids: Set<UUID>) { deletionIDs = ids; confirmingDelete = !ids.isEmpty }
    private func openEditor(_ record: PhoneTrainingSession? = nil) {
        if let saved = store.editorDrafts.first(where: { $0.recordID == record?.id }) { editor = saved; return }
        let exercise = record?.exercise ?? filter.exercise ?? store.lastExercise
        var draft = RecordEditorDraft(recordID: record?.id, date: record?.startTime ?? Date(), sets: record?.sets.map(RecordSetDraft.init) ?? [RecordSetDraft(exercise: exercise, weight: store.suggestedWeight(for: exercise).map { $0.formatted(.number.grouping(.never)) } ?? "")])
        draft.duration = record?.recordedDuration.map { ($0 / 60).formatted(.number.grouping(.never)) } ?? ""
        draft.summaryReps = record.map { String($0.totalReps) } ?? ""
        draft.summaryWeight = record.map { $0.maxWeight.formatted(.number.grouping(.never)) } ?? ""
        draft.note = record?.note ?? ""; editor = draft
    }
}

struct RecordRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: PhoneTrainingSession
    var filter = RecordFilter()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.exercises.filter { filter.exercise == nil || $0 == filter.exercise }, id: \.self) { exercise in
                        RecordExerciseLabel(exercise: exercise, size: 26)
                    }
                }.font(.body.weight(.medium)).frame(width: typeSize.isAccessibilitySize ? nil : 132, alignment: .leading)
                Text(String(localized: "\(filter.reps(item)) 次")).font(.body.weight(.medium)).monospacedDigit()
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metadata }
                VStack(alignment: .leading, spacing: 4) { metadata }
            }.font(.caption).foregroundStyle(Studio.muted)
        }.frame(minHeight: 68).foregroundStyle(Studio.ink)
    }
    @ViewBuilder private var metadata: some View {
        Text(item.startTime.formatted(date: .omitted, time: .shortened))
        Text(String(localized: "\(filter.weight(item).formatted()) 公斤"))
        if let duration = item.displayDuration { Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))).monospacedDigit() }
        if !(item.note ?? "").isEmpty { Image(systemName: "text.alignleft").accessibilityLabel(String(localized: "有备注")) }
    }
}

struct RecordDetailView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var store: PhoneWorkoutStore
    let id: UUID
    var edit: (PhoneTrainingSession) -> Void
    var delete: (PhoneTrainingSession) -> Void
    var body: some View {
        Group {
            if let item = store.history.first(where: { $0.id == id }) {
                List {
                    if let error = store.storageError { Text(error).foregroundStyle(.red) }
                    Section {
                        ForEach(item.exercises, id: \.self) { exercise in
                            RecordExerciseLabel(exercise: exercise, size: 32).font(.title2.weight(.semibold))
                        }
                        Text(item.startTime.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(Studio.muted)
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 24))) {
                            RecordMetric(title: String(localized: "总次数"), value: String(localized: "\(item.totalReps) 次"))
                                .accessibilityElement(children: .ignore).accessibilityLabel(String(localized: "总次数"))
                                .accessibilityValue(String(localized: "\(item.totalReps) 次")).accessibilityIdentifier("record-total-reps")
                            RecordMetric(title: String(localized: "最大重量"), value: String(localized: "\(item.maxWeight.formatted()) 公斤"))
                        }.padding(.vertical, 8)
                    }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                    if item.displayDuration != nil || item.activeDuration != nil || item.volume != nil {
                        Section {
                            if let duration = item.displayDuration { LabeledContent(String(localized: "训练总用时"), value: Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))) }
                            if let duration = item.activeDuration { LabeledContent(String(localized: "动作时长（估计）"), value: Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))) }
                            if let volume = item.volume { LabeledContent(String(localized: "总训练量"), value: String(localized: "\(volume.formatted()) 公斤")) }
                        }.listRowBackground(Studio.surface)
                    }
                    if !item.isSummary {
                        ForEach(item.exercises, id: \.self) { exercise in
                            Section {
                                ForEach(Array(item.sets.filter { $0.exercise == exercise }.enumerated()), id: \.element.id) { index, set in
                                    HStack {
                                        Text("\(index + 1)").foregroundStyle(Studio.muted)
                                        Spacer()
                                        Text("\(set.weight.formatted()) 公斤 × \(set.reps) 次").monospacedDigit()
                                    }.frame(minHeight: 28)
                                }
                            } header: { RecordExerciseLabel(exercise: exercise, size: 20) }
                                .listRowBackground(Studio.surface)
                        }
                    }
                    if let note = item.note, !note.isEmpty { Section(String(localized: "备注")) { Text(note).textSelection(.enabled) }.listRowBackground(Studio.surface) }
                    Section { Button(String(localized: "删除记录"), role: .destructive) { delete(item) } }.listRowBackground(Studio.surface)
                }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "编辑")) { edit(item) }.accessibilityIdentifier("edit-record") } }
            } else { ContentUnavailableView(String(localized: "记录不存在"), systemImage: "clock") }
        }.recordListStyle().navigationTitle(String(localized: "训练详情")).navigationBarTitleDisplayMode(.inline)
    }
}
