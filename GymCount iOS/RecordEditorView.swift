import SwiftUI

struct RecordEditorView: View {
    @EnvironmentObject private var store: PhoneWorkoutStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let initial: RecordEditorDraft
    let onSave: () -> Void
    @State private var draft: RecordEditorDraft
    @State private var confirmingExit = false
    @State private var error: String?
    @State private var saving = false
    @State private var attempted = false
    @State private var finishing = false
    @FocusState private var focus: String?
    @Namespace private var fieldSpace
    @ScaledMetric(relativeTo: .subheadline) private var weightWidth: CGFloat = 66
    @ScaledMetric(relativeTo: .subheadline) private var repsWidth: CGFloat = 50
    private var expandedRows: Bool { typeSize >= .xxLarge }
    init(initial: RecordEditorDraft, onSave: @escaping () -> Void) {
        self.initial = initial; self.onSave = onSave; _draft = State(initialValue: initial)
    }
    private var record: PhoneTrainingSession? { store.history.first { $0.id == draft.recordID } }
    private var summary: Bool { record?.isSummary == true }
    private var changed: Bool { draft != initial }
    private var duration: Double? { Double(draft.duration.replacingOccurrences(of: ",", with: ".")).map { $0 * 60 } }
    private var validDuration: Bool { draft.duration.isEmpty || (duration.map { $0.isFinite && (0...86400).contains($0) } ?? false) }
    private var validSummary: Bool {
        guard let reps = Int(draft.summaryReps), (0...1_000_000).contains(reps),
              let weight = Double(draft.summaryWeight.replacingOccurrences(of: ",", with: ".")) else { return false }
        return weight.isFinite && (0...500).contains(weight)
    }
    private var valid: Bool {
        draft.note.count <= 2000 && (summary ? validSummary : !draft.sets.isEmpty && draft.sets.allSatisfy { $0.parsed != nil } && validDuration)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error { validation(error) }
                    if draft.recordID != nil && record == nil {
                        validation(String(localized: "记录不存在"))
                    } else if summary {
                        RecordExerciseLabel(exercise: record!.exercise, size: 28).font(.headline)
                        VStack(spacing: 16) {
                            labeledField(String(localized: "总次数"), text: $draft.summaryReps, key: "summary-reps", decimal: false)
                            labeledField(String(localized: "最大重量（公斤）"), text: $draft.summaryWeight, key: "summary-weight", decimal: true)
                            if !validSummary { validation(String(localized: "请输入有效次数和重量")) }
                        }.padding(16).background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        DatePicker(String(localized: "日期"), selection: $draft.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        Text(String(localized: "训练组")).font(.headline)
                        VStack(spacing: 0) {
                            if !expandedRows { setColumnLabels }
                            ForEach($draft.sets) { $set in
                                setRow($set).id(set.id.uuidString)
                                    .transition(RecordMotion.row(reduced: reduceMotion))
                            }
                        }.padding(12).background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !summary && (record == nil || record?.manualEntry == true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "时长（分钟，可选）")).font(.subheadline).foregroundStyle(Studio.muted)
                            compactEntry($draft.duration, key: "duration", decimal: true, label: String(localized: "时长（分钟，可选）"))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Studio.line, lineWidth: 0.5).allowsHitTesting(false))
                            if !validDuration { validation(String(localized: "时长应在 0–1440 分钟之间")) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "备注（可选）")).font(.subheadline).foregroundStyle(Studio.muted)
                        TextField("", text: $draft.note, axis: .vertical)
                            .lineLimit(3...5).focused($focus, equals: "note").id("note")
                            .padding(12).background(Studio.surface, in: RoundedRectangle(cornerRadius: 10))
                            .modifier(RecordFocusOutline(focused: focus == "note", space: fieldSpace))
                            .accessibilityLabel(String(localized: "备注"))
                        if draft.note.count > 2000 { validation(String(localized: "备注最多 2000 字")) }
                    }
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }.scrollDismissesKeyboard(.interactively).background(Studio.background)
                .safeAreaInset(edge: .bottom, spacing: 0) { commandBar }
                .navigationTitle(draft.recordID == nil ? String(localized: "补记训练") : String(localized: "编辑记录"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Studio.background, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "取消")) {
                            focus = nil
                            if changed || store.editorDrafts.contains(where: { $0.id == draft.id }) { confirmingExit = true }
                            else { dismiss() }
                        }
                    }
                }
                .confirmationDialog(String(localized: "保留这次编辑？"), isPresented: $confirmingExit, titleVisibility: .visible) {
                    Button(String(localized: "保留草稿")) {
                        if store.saveDraft(draft) { finishing = true; dismiss() } else { error = store.storageError }
                    }
                    Button(String(localized: "放弃修改"), role: .destructive) {
                        if store.discardEditorDraft(draft.id) { finishing = true; dismiss() } else { error = store.storageError }
                    }
                    Button(String(localized: "继续编辑"), role: .cancel) {}
                }
        }.tint(Studio.accent).foregroundStyle(Studio.ink)
            .animation(RecordMotion.animation(reduced: reduceMotion), value: draft.sets.count)
            .animation(RecordMotion.animation(reduced: reduceMotion), value: attempted)
            .interactiveDismissDisabled(changed || store.editorDrafts.contains { $0.id == draft.id })
            .task(id: draft) {
                guard changed, !finishing else { return }
                do { try await Task.sleep(for: .milliseconds(500)); try Task.checkCancellation() }
                catch { return }
                guard !finishing else { return }
                if !store.saveDraft(draft) { error = store.storageError }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, changed, !finishing { if !store.saveDraft(draft) { error = store.storageError } }
            }
    }
    private var commandBar: some View {
        VStack(spacing: 0) {
            // Keep keyboard actions in our measured safe-area layout. The system
            // .keyboard ToolbarItemGroup produced a negative frame during focus.
            if focus != nil {
                HStack {
                    Button(String(localized: "下一项")) { nextField() }.frame(minHeight: 44)
                    Spacer(minLength: 8)
                    Button(String(localized: "完成")) { focus = nil }.frame(minHeight: 44)
                }.padding(.horizontal, 20)
                    .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: 0.5) }
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                if !summary && (draft.recordID == nil || record != nil) {
                    Button { appendSet() } label: {
                        Label(String(localized: "添加一组"), systemImage: "plus").font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.disabled(draft.sets.count >= 500).accessibilityIdentifier("add-record-set")
                    if draft.recordID == nil {
                        Button { reuseLast() } label: {
                            Label(String(localized: "参考上次"), systemImage: "doc").font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.disabled(store.lastSets(for: draft.sets.last?.exercise ?? store.lastExercise).isEmpty)
                    }
                } else if !typeSize.isAccessibilitySize { Spacer() }
                Button(action: save) {
                    Group { if saving { ProgressView().tint(Studio.onAccent) } else { Text(String(localized: "保存")) } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Studio.onAccent)
                        .frame(minWidth: 76, minHeight: 44)
                        .background(Studio.accent, in: RoundedRectangle(cornerRadius: 8))
                }.disabled(saving || (draft.recordID != nil && record == nil)).accessibilityIdentifier("save-record")
            }.padding(.horizontal, 16).padding(.vertical, 9)
        }.buttonStyle(RecordPressStyle()).background(Studio.background)
            .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 0.5) }
    }
    private var setColumnLabels: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 18, height: 1)
            Text(String(localized: "动作")).frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "公斤")).frame(width: weightWidth)
            Text(String(localized: "次数")).frame(width: repsWidth)
            Color.clear.frame(width: 44, height: 1)
        }.font(.caption).foregroundStyle(Studio.muted)
            .accessibilityHidden(true)
            .padding(.bottom, 8)
    }
    private func setRow(_ set: Binding<RecordSetDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if expandedRows {
                HStack(spacing: 8) {
                    setNumber(set.wrappedValue)
                    exercisePicker(set)
                    removeButton(set.wrappedValue)
                }
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
                    entry(String(localized: "公斤"), text: set.weight, key: set.wrappedValue.id.uuidString + ":weight", decimal: true, label: String(localized: "重量（公斤）"))
                    entry(String(localized: "次数"), text: set.reps, key: set.wrappedValue.id.uuidString + ":reps", decimal: false, label: String(localized: "次数"))
                }
            } else {
                HStack(spacing: 6) {
                    setNumber(set.wrappedValue)
                    exercisePicker(set)
                    compactEntry(set.weight, key: set.wrappedValue.id.uuidString + ":weight", decimal: true, label: String(localized: "重量（公斤）"))
                        .frame(width: weightWidth)
                    compactEntry(set.reps, key: set.wrappedValue.id.uuidString + ":reps", decimal: false, label: String(localized: "次数"))
                        .frame(width: repsWidth)
                    removeButton(set.wrappedValue)
                }
            }
            if attempted && set.wrappedValue.parsed == nil { validation(String(localized: "重量 0–500 公斤，次数 1–999")) }
        }.frame(minHeight: 70).padding(.vertical, expandedRows ? 4 : 0)
    }
    private func setNumber(_ set: RecordSetDraft) -> some View {
        Text("\((draft.sets.firstIndex { $0.id == set.id } ?? 0) + 1)")
            .font(.caption.monospacedDigit()).foregroundStyle(Studio.muted).frame(width: 18)
    }
    private func exercisePicker(_ set: Binding<RecordSetDraft>) -> some View {
        Menu {
            Picker(String(localized: "动作"), selection: set.exercise) {
                ForEach(ExerciseType.allCases, id: \.self) { Label($0.recordName, image: $0.icon).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                RecordExerciseIcon(exercise: set.wrappedValue.exercise, size: 22)
                Text(set.wrappedValue.exercise.recordName).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Studio.muted)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.borderless).foregroundStyle(Studio.ink)
            .accessibilityLabel(String(localized: "动作")).accessibilityValue(set.wrappedValue.exercise.recordName)
    }
    private func removeButton(_ set: RecordSetDraft) -> some View {
        Button(role: .destructive) {
            if let key = focus, key.hasPrefix(set.id.uuidString) { focus = nil }
            withAnimation(RecordMotion.animation(reduced: reduceMotion)) { draft.sets.removeAll { $0.id == set.id } }
        } label: {
            Image(systemName: "minus.circle").font(.system(size: 18)).foregroundStyle(Studio.muted)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.borderless).disabled(draft.sets.count <= 1)
            .opacity(draft.sets.count <= 1 ? 0.3 : 1).accessibilityLabel(String(localized: "移除此组"))
    }
    private func compactEntry(_ text: Binding<String>, key: String, decimal: Bool, label: String) -> some View {
        TextField("—", text: text).keyboardType(decimal ? .decimalPad : .numberPad)
            .focused($focus, equals: key).accessibilityLabel(label)
            .font(.subheadline.weight(.medium)).monospacedDigit().multilineTextAlignment(.center)
            .frame(minHeight: 44).background(Studio.background, in: RoundedRectangle(cornerRadius: 8))
            .modifier(RecordFocusOutline(focused: focus == key, space: fieldSpace))
    }
    private func entry(_ title: String, text: Binding<String>, key: String, decimal: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            TextField("—", text: text).keyboardType(decimal ? .decimalPad : .numberPad)
                .focused($focus, equals: key).accessibilityLabel(label).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(Studio.muted)
        }.padding(.horizontal, 12).frame(minHeight: 44).background(Studio.background, in: RoundedRectangle(cornerRadius: 10))
            .modifier(RecordFocusOutline(focused: focus == key, space: fieldSpace))
    }
    private func labeledField(_ title: String, text: Binding<String>, key: String, decimal: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title).fixedSize(horizontal: false, vertical: true)
            TextField("—", text: text).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .keyboardType(decimal ? .decimalPad : .numberPad).focused($focus, equals: key).accessibilityLabel(title)
                .frame(minHeight: 44).modifier(RecordFocusOutline(focused: focus == key, space: fieldSpace))
        }.id(key)
    }
    private func validation(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.red).accessibilityIdentifier("entry-error") }
    private func appendSet() {
        let last = draft.sets.last
        let next = RecordSetDraft(exercise: last?.exercise ?? store.lastExercise, weight: last?.weight ?? "")
        withAnimation(RecordMotion.animation(reduced: reduceMotion)) { draft.sets.append(next) }; focus = next.id.uuidString + ":reps"
    }
    private func reuseLast() {
        let exercise = draft.sets.last?.exercise ?? store.lastExercise
        let prior = store.lastSets(for: exercise)
        guard !prior.isEmpty else { return }
        // Only use the template when no repetitions have been entered.
        if draft.sets.contains(where: { !$0.reps.isEmpty }) {
            error = String(localized: "请先清空次数，再参考上次")
            return
        }
        draft.sets = prior.map { RecordSetDraft(exercise: $0.exercise, weight: $0.weight.formatted(.number.grouping(.never))) }
        focus = draft.sets.first.map { $0.id.uuidString + ":reps" }
    }
    private func nextField() {
        let keys = summary ? ["summary-reps", "summary-weight", "note"] : draft.sets.flatMap { [$0.id.uuidString + ":weight", $0.id.uuidString + ":reps"] } + ["duration", "note"]
        if let current = focus, let index = keys.firstIndex(of: current), index + 1 < keys.count { focus = keys[index + 1] }
        else { focus = keys.first }
    }
    private func save() {
        attempted = true; error = nil
        guard valid else { return }
        saving = true; focus = nil
        let sets = draft.sets.compactMap(\.parsed)
        let saved: Bool
        if let id = draft.recordID {
            saved = store.updateRecord(id: id, date: draft.date, sets: sets, duration: duration,
                summaryReps: Int(draft.summaryReps), summaryWeight: Double(draft.summaryWeight.replacingOccurrences(of: ",", with: ".")), note: draft.note, draftID: draft.id)
        } else { saved = store.addRecord(date: draft.date, sets: sets, duration: duration, note: draft.note, draftID: draft.id) }
        saving = false
        if saved { finishing = true; onSave(); dismiss() }
        else { error = store.storageError ?? String(localized: "保存失败，请检查输入后重试。") }
    }
}
