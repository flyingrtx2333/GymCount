import SwiftUI
import Combine

enum Studio {
    static let title = Font.system(size: 30, weight: .semibold)
    static let body = Font.system(size: 17)
    static let button = Font.system(size: 17, weight: .semibold)
    static let detail = Font.system(size: 14)
    static let inset: CGFloat = 22
    static let spacing: CGFloat = 16
    static let buttonHeight: CGFloat = 48
    static let background = Color.black
    static let ink = Color.white
    static let accent = Color(red: 181/255, green: 244/255, blue: 216/255)
    static let muted = Color.white.opacity(0.55)
    static let line = Color.white.opacity(0.10)
    static let surface = Color(red: 18/255, green: 20/255, blue: 20/255)
}

struct PhoneContentView: View {
    @EnvironmentObject private var store: PhoneWorkoutStore
    #if GYMCOUNT_SYNC
    @EnvironmentObject private var capture: PhoneCaptureStore
    #endif
    @AppStorage("phone.defaultWeight") private var weight = 50.0
    @State private var exercise: ExerciseType = .benchPress
    @State private var tab = 0
    @State private var confirmingFinish = false
    @State private var historyEditMode: EditMode = .inactive
    @State private var editingSet = false
    @State private var inputWeight = ""
    @State private var inputReps = ""
    @State private var pendingExercise: ExerciseType?
    @State private var confirmingSwitch = false
    @State private var confirmingReuse = false
    @Environment(\.scenePhase) private var scenePhase
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func name(_ exercise: ExerciseType) -> String {
        switch exercise {
        case .benchPress: return String(localized: "卧推")
        case .squat: return String(localized: "深蹲")
        case .deadlift: return String(localized: "硬拉")
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            training.tag(0)
            history.tag(1)
            settings.tag(2)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .tint(Studio.accent)
        .foregroundStyle(Studio.ink)
        .preferredColorScheme(.dark)
        .onReceive(clock) { store.checkRest(now: $0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.checkRest()
                #if GYMCOUNT_SYNC
                capture.requestWorkoutHistory()
                #endif
            }
        }
        .sensoryFeedback(.success, trigger: store.restFinished) { _, finished in finished }
        .sheet(isPresented: $editingSet) { setEditor }
        .alert(String(localized: "替换当前组？"), isPresented: $confirmingReuse) {
            Button(String(localized: "替换本组"), role: .destructive) { store.reuseSuggestedSet(replacingDraft: true) }
            Button(String(localized: "保留本组"), role: .cancel) {}
        } message: {
            Text(String(localized: "沿用上次会替换当前组已输入的重量和次数，已保存的组不受影响。"))
        }
        .confirmationDialog(String(localized: "当前组还有未保存的次数"), isPresented: $confirmingSwitch, titleVisibility: .visible) {
            Button(String(localized: "保存本组并切换")) {
                store.completeSet()
                switchExercise()
            }
            Button(String(localized: "放弃本组并切换"), role: .destructive) {
                store.discardDraft()
                switchExercise()
            }
            Button(String(localized: "继续本组"), role: .cancel) { pendingExercise = nil }
        }
    }

    private var training: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text(String(localized: "训练")).font(Studio.title)
                            Spacer()
                        }
                        .padding(.bottom, 26)
                        if let error = store.storageError {
                            Text(error).font(.footnote).foregroundStyle(.red).padding(.bottom, 12)
                        }
                        if let session = store.session {
                            activeTraining(session)
                        } else {
                            readyTraining
                        }
                    }
                    .padding(.horizontal, Studio.inset)
                    .padding(.top, -8)
                    .padding(.bottom, 20)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
            }
            .background(Studio.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(String(localized: "结束当前训练并保存记录？"), isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button(String(localized: "结束并保存")) { store.finish(); tab = 1 }
                    .accessibilityIdentifier("confirm-finish")
                Button(String(localized: "继续训练"), role: .cancel) {}
            }
        }
    }

    private var readyTraining: some View {
        VStack(spacing: 0) {
            Text(String(localized: "开始下一组"))
                .font(.system(size: 26, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            HStack(spacing: 10) {
                ForEach(ExerciseType.allCases, id: \.self) { item in
                    Button { exercise = item } label: {
                        Text(name(item)).font(.system(size: 19, weight: exercise == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(exercise == item ? Studio.accent : Studio.ink)
                            .background(exercise == item ? Studio.accent.opacity(0.10) : Studio.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(exercise == item ? Studio.accent.opacity(0.3) : .clear, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(exercise == item ? .isSelected : [])
                }
            }
            .padding(.bottom, 23)
            exerciseImage(exercise, size: 158)
            Text(name(exercise)).font(.system(size: 24, weight: .medium))
                .padding(.top, 5).padding(.bottom, 21)
            HStack(spacing: 0) {
                weightButton(String(localized: "减少重量"), symbol: "minus", disabled: weight <= 0) { weight = max(0, weight - 2.5) }
                Spacer(minLength: 8)
                Button { openEditor() } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(weight, format: .number.precision(.fractionLength(0...1)))
                            .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.65)
                        Text(String(localized: "公斤")).font(.system(size: 17)).foregroundStyle(Studio.muted)
                    }
                }.buttonStyle(.plain).accessibilityLabel(String(localized: "输入训练重量"))
                Spacer(minLength: 8)
                weightButton(String(localized: "增加重量"), symbol: "plus", disabled: weight >= 500) { weight = min(500, weight + 2.5) }
            }
            .padding(.horizontal, 24).padding(.bottom, 14)
            Button { store.start(exercise: exercise, weight: weight) } label: {
                Text(String(localized: "开始训练"))
            }.buttonStyle(StudioPrimaryButton()).disabled(store.storageError != nil)
                .padding(.top, 10).padding(.bottom, 16)
            previousTraining(exercise, canStart: true)
                .padding(.bottom, 24)
            Rectangle().fill(Studio.line).frame(height: 0.5)
            Button { tab = 1 } label: {
                VStack(spacing: 10) {
                    Image(systemName: "clock").font(.system(size: 25, weight: .light))
                        .foregroundStyle(Studio.muted)
                    if let latest = store.history.first {
                        Text(String(localized: "最近训练 · \(latest.exercises.map(name).joined(separator: "、")) · \(latest.totalReps) 次"))
                            .font(.system(size: 15)).foregroundStyle(Studio.muted)
                    } else {
                        Text(String(localized: "还没有训练记录")).font(.system(size: 15)).foregroundStyle(Studio.muted)
                    }
                    HStack(spacing: 8) {
                        Text(String(localized: "查看历史"))
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium))
                    }.font(.system(size: 16, weight: .medium)).foregroundStyle(Studio.accent)
                }.frame(maxWidth: .infinity).padding(.top, 30).padding(.bottom, 4)
            }.buttonStyle(.plain)
        }
    }

    private func exerciseImage(_ exercise: ExerciseType, size: CGFloat) -> some View {
        Circle().fill(Studio.surface)
            .overlay {
                Image(exercise.icon).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(Studio.ink).padding(size * 0.19)
            }
            .frame(width: size, height: size).accessibilityHidden(true)
    }

    private func weightButton(_ title: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 24, weight: .regular))
                .frame(width: 49, height: 49).background(Studio.surface, in: Circle())
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1).accessibilityLabel(title)
    }

    private func activeTraining(_ session: PhoneTrainingSession) -> some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "本次训练")).font(.system(size: 26, weight: .semibold))
                    Text(String(localized: "已保存 \(session.sets.filter { !$0.imported }.count) 组 · \(session.totalReps) 次"))
                        .font(Studio.detail).foregroundStyle(Studio.muted)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(max(0, context.date.timeIntervalSince(session.startTime)))
                        .formatted(.time(pattern: .minuteSecond)))
                        .font(Studio.detail).monospacedDigit().foregroundStyle(Studio.muted)
                }
            }
            HStack(spacing: 10) {
                ForEach(ExerciseType.allCases, id: \.self) { item in
                    Button { requestExercise(item) } label: {
                        Text(name(item)).font(Studio.button)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(session.exercise == item ? Studio.accent : Studio.ink)
                            .background(session.exercise == item ? Studio.accent.opacity(0.1) : Studio.surface, in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("active-exercise-" + item.rawValue)
                        .accessibilityAddTraits(session.exercise == item ? .isSelected : [])
                }
            }
            if let end = session.restEndsAt {
                restCard(end)
            } else if store.restFinished {
                Label(String(localized: "休息结束，准备下一组"), systemImage: "checkmark.circle")
                    .font(Studio.body).foregroundStyle(Studio.accent)
                    .accessibilityIdentifier("rest-finished")
            }
            VStack(spacing: 16) {
                HStack {
                    exerciseImage(session.exercise, size: 48)
                    Text(String(localized: "\(name(session.exercise)) · 第 \(store.nextSetNumber) 组")).font(.headline)
                    Spacer()
                }
                HStack {
                    weightButton(String(localized: "本组减少重量"), symbol: "minus", disabled: session.weight <= 0) {
                        store.setWeight(max(0, session.weight - 2.5))
                    }
                    Spacer()
                    Button { openEditor() } label: {
                        Text("\(session.weight, specifier: "%.1f") 公斤")
                            .font(.system(size: 27, weight: .semibold)).monospacedDigit()
                    }.buttonStyle(.plain).accessibilityLabel(String(localized: "修改本组重量"))
                    Spacer()
                    weightButton(String(localized: "本组增加重量"), symbol: "plus", disabled: session.weight >= 500) {
                        store.setWeight(min(500, session.weight + 2.5))
                    }
                }
                HStack(spacing: 18) {
                    Button(action: store.removeRep) {
                        Image(systemName: "minus").frame(width: 48, height: 48)
                    }.buttonStyle(.plain).disabled(session.reps == 0).accessibilityLabel(String(localized: "撤销一次"))
                    Text("\(session.reps)").font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit().frame(maxWidth: .infinity)
                        .accessibilityLabel(String(localized: "已完成 \(session.reps) 次"))
                    Button(action: store.addRep) {
                        Image(systemName: "plus").frame(width: 48, height: 48)
                    }.buttonStyle(.plain).disabled(session.reps >= 999).accessibilityLabel(String(localized: "增加一次"))
                }.font(.system(size: 25)).sensoryFeedback(.increase, trigger: session.reps)
                Button(String(localized: "直接填次数")) { openEditor() }
                    .font(Studio.body).foregroundStyle(Studio.accent).frame(minHeight: 44)
                if let suggested = store.suggestedSet {
                    Button {
                        if session.reps > 0 { confirmingReuse = true }
                        else { store.reuseSuggestedSet() }
                    } label: {
                        Label("沿用上次：\(suggested.weight, specifier: "%.1f") 公斤 × \(suggested.reps) 次", systemImage: "arrow.counterclockwise")
                            .font(Studio.detail).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(Studio.accent).accessibilityIdentifier("reuse-last-set")
                }
                Button(session.restEndsAt == nil ? String(localized: "完成本组 · 开始休息") : String(localized: "完成本组 · 重新计时"), action: store.completeSet)
                    .buttonStyle(StudioPrimaryButton()).disabled(session.reps == 0 || store.storageError != nil)
                    .accessibilityIdentifier("complete-set")
                Text(String(localized: "完成后保存本组，次数归零；整场训练结束后统一归档。"))
                    .font(.caption).foregroundStyle(Studio.muted)
            }.padding(18).background(Studio.surface, in: RoundedRectangle(cornerRadius: 24))
            if !session.sets.isEmpty {
                savedSets(session)
            }
            if session.sets.isEmpty && session.reps == 0 {
                Button(String(localized: "取消本次训练"), action: store.cancelEmptyTraining)
                    .buttonStyle(StudioSecondaryButton())
            } else {
                Button(String(localized: "结束并保存")) { confirmingFinish = true }
                    .buttonStyle(StudioSecondaryButton())
                    .accessibilityIdentifier("finish-training")
                if session.reps > 0 {
                    Text(String(localized: "当前组 \(session.reps) 次也会一并保存。"))
                        .font(.caption).foregroundStyle(Studio.muted)
                }
            }
        }
    }

    private func restCard(_ end: Date) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "组间休息")).font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(max(0, ceil(end.timeIntervalSince(context.date))))
                        .formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }
            Spacer()
            Button(String(localized: "跳过休息"), action: store.skipRest)
                .font(Studio.button).frame(minHeight: 44)
        }.foregroundStyle(Studio.accent).padding(18)
            .background(Studio.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rest-card")
    }

    private func savedSets(_ session: PhoneTrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "本次已记录")).font(.headline)
                Spacer()
                if session.reps == 0 && session.sets.last?.imported == false {
                    Button(String(localized: "撤回上一组"), action: store.undoLastSet)
                        .font(Studio.detail).frame(minHeight: 44)
                }
            }
            ForEach(session.exercises, id: \.self) { exercise in
                exerciseSets(session, exercise: exercise)
            }
        }
    }

    @ViewBuilder
    private func exerciseSets(_ session: PhoneTrainingSession, exercise: ExerciseType) -> some View {
        let sets = session.sets.filter { $0.exercise == exercise }
        ForEach(sets.filter { $0.imported }) { set in
            setRow(set, number: 0)
        }
        ForEach(Array(sets.filter { !$0.imported }.enumerated()), id: \.element.id) { index, set in
            setRow(set, number: index + 1)
        }
    }

    private func setRow(_ set: PhoneTrainingSet, number: Int) -> some View {
        HStack {
            Text(set.imported ? String(localized: "旧版次数") : "\(number)")
                .font(Studio.detail).foregroundStyle(Studio.muted).frame(minWidth: 24)
            Text(name(set.exercise)).font(Studio.body)
            Spacer()
            Text("\(set.weight, specifier: "%.1f") 公斤 × \(set.reps) 次")
                .font(Studio.detail).monospacedDigit().foregroundStyle(Studio.accent)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func previousTraining(_ exercise: ExerciseType, canStart: Bool) -> some View {
        let sets = store.lastSets(for: exercise)
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "上次\(name(exercise))")).font(.headline)
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    Text("第 \(index + 1) 组 · \(set.weight, specifier: "%.1f") 公斤 × \(set.reps) 次")
                        .font(Studio.detail).foregroundStyle(Studio.muted)
                }
                if canStart {
                    Button(String(localized: "沿用上次开始")) { store.start(exercise: exercise, weight: weight, reuseLast: true) }
                        .buttonStyle(StudioSecondaryButton()).disabled(store.storageError != nil)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(18).background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func requestExercise(_ exercise: ExerciseType) {
        guard exercise != store.session?.exercise else { return }
        pendingExercise = exercise
        if (store.session?.reps ?? 0) > 0 { confirmingSwitch = true }
        else { switchExercise() }
    }

    private func switchExercise() {
        if let pendingExercise { store.selectExercise(pendingExercise, defaultWeight: weight) }
        pendingExercise = nil
    }

    private func openEditor() {
        inputWeight = String(store.session?.weight ?? weight)
        inputReps = String(store.session?.reps ?? 0)
        editingSet = true
    }

    private var parsedWeight: Double? {
        guard let value = Double(inputWeight.replacingOccurrences(of: ",", with: ".")), value.isFinite, (0...500).contains(value) else { return nil }
        return value
    }

    private var parsedReps: Int? {
        guard let value = Int(inputReps), (0...999).contains(value) else { return nil }
        return value
    }

    private var setEditor: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(String(localized: "重量（公斤）"))
                        TextField("0–500", text: $inputWeight).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).accessibilityIdentifier("set-weight-input")
                    }
                    if store.session != nil {
                        HStack {
                            Text(String(localized: "次数"))
                            TextField("0–999", text: $inputReps).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).accessibilityIdentifier("set-reps-input")
                        }
                        HStack {
                            ForEach([5, 8, 10, 12, 15], id: \.self) { reps in
                                Button("\(reps)") { inputReps = String(reps) }
                                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
                                    .accessibilityLabel(String(localized: "填入 \(reps) 次"))
                            }
                        }
                    }
                } footer: {
                    Text(String(localized: "重量支持 0–500 公斤，自重动作可填 0。次数支持 0–999。"))
                }
            }
            .navigationTitle(store.session == nil ? String(localized: "输入重量") : String(localized: "快速录入本组"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { editingSet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "确认")) {
                        guard let parsedWeight else { return }
                        if store.session != nil, let parsedReps {
                            store.setWeight(parsedWeight)
                            store.setReps(parsedReps)
                        } else { weight = parsedWeight }
                        editingSet = false
                    }.disabled(parsedWeight == nil || (store.session != nil && parsedReps == nil))
                        .accessibilityIdentifier("confirm-set-input")
                }
            }
        }.tint(Studio.accent).preferredColorScheme(.dark)
    }

    private var history: some View {
        NavigationStack {
            List {
                if let error = store.storageError { Text(error).foregroundStyle(.red) }
                #if GYMCOUNT_SYNC
                if !capture.workoutSyncMessage.isEmpty {
                    Text(capture.workoutSyncMessage).font(Studio.detail).foregroundStyle(Studio.muted)
                        .listRowBackground(Studio.surface)
                }
                #endif
                ForEach(store.history) { item in
                    NavigationLink { historyDetail(item) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.exercises.map(name).joined(separator: " · ")).font(.headline)
                                Spacer()
                                Text(String(localized: "\(item.totalReps) 次")).font(.headline).foregroundStyle(Studio.accent)
                            }
                            Text(item.startTime.formatted(.dateTime.month().day().hour().minute()))
                            if item.watchSummary != nil {
                                Text("Apple Watch · \(Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)))")
                            } else if item.legacySummary != nil {
                                Text(String(localized: "旧版记录 · \(Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)))"))
                            } else {
                                Text(String(localized: "\(item.sets.filter { !$0.imported }.count) 组 · \(Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)))"))
                            }
                        }.font(Studio.detail).foregroundStyle(Studio.muted).padding(.vertical, 8)
                    }.listRowBackground(Studio.surface).listRowSeparatorTint(Studio.line)
                }.onDelete(perform: store.deleteHistory)
            }
            .scrollContentBackground(.hidden).background(Studio.background)
            .overlay {
                if store.history.isEmpty && store.storageError == nil {
                    ContentUnavailableView {
                        Label(String(localized: "还没有训练记录"), systemImage: "clock")
                    } description: {
                        Text(String(localized: "完成一次训练后，可以在这里查看每个动作和每组表现。"))
                    } actions: {
                        Button(store.session == nil ? String(localized: "开始训练") : String(localized: "继续训练")) {
                            historyEditMode = .inactive
                            tab = 0
                        }
                        .buttonStyle(StudioPrimaryButton())
                        .frame(maxWidth: 240)
                        .accessibilityIdentifier("history-start-training")
                    }
                }
            }
            .navigationTitle(String(localized: "训练记录"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $historyEditMode)
            .toolbar {
                #if GYMCOUNT_SYNC
                Button { capture.requestWorkoutHistory(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }.accessibilityLabel(String(localized: "同步手表记录")).disabled(store.storageError != nil)
                #endif
                Button(historyEditMode == .active ? String(localized: "完成") : String(localized: "编辑")) {
                    withAnimation { historyEditMode = historyEditMode == .active ? .inactive : .active }
                }.disabled(store.storageError != nil)
            }
            .toolbarBackground(Studio.background, for: .navigationBar)
        }
    }

    private func historyDetail(_ item: PhoneTrainingSession) -> some View {
        List {
            Section(String(localized: "训练总结")) {
                LabeledContent(String(localized: "开始时间"), value: item.startTime.formatted(date: .abbreviated, time: .shortened))
                LabeledContent(String(localized: "训练时长"), value: Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)))
                LabeledContent(String(localized: "总次数"), value: String(localized: "\(item.totalReps) 次"))
                if let volume = item.volume {
                    LabeledContent(String(localized: "总训练量"), value: String(localized: "\(volume.formatted(.number.precision(.fractionLength(0...1)))) 公斤"))
                    Text(String(localized: "训练量 = 各组重量 × 次数之和")).font(.caption).foregroundStyle(Studio.muted)
                }
            }.listRowBackground(Studio.surface)
            if let old = item.watchSummary ?? item.legacySummary {
                Section(item.watchSummary != nil ? String(localized: "Apple Watch 训练记录") : String(localized: "旧版训练记录")) {
                    LabeledContent(String(localized: "动作"), value: name(old.exerciseType))
                    LabeledContent(String(localized: "最大重量"), value: String(localized: "\(old.maxWeight.formatted()) 公斤"))
                    Text(item.watchSummary != nil ? String(localized: "来自 Apple Watch 的训练汇总，没有各组明细。") : String(localized: "旧版仅保存汇总信息，没有各组明细。"))
                        .font(.footnote).foregroundStyle(Studio.muted)
                }.listRowBackground(Studio.surface)
            } else {
                ForEach(item.exercises, id: \.self) { exercise in
                    Section(name(exercise)) {
                        exerciseSets(item, exercise: exercise)
                    }.listRowBackground(Studio.surface)
                }
            }
        }.scrollContentBackground(.hidden).background(Studio.background)
            .navigationTitle(String(localized: "训练详情")).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Studio.background, for: .navigationBar)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section(String(localized: "训练偏好")) {
                    Stepper(value: $weight, in: 0...500, step: 2.5) {
                        Text("默认重量：\(weight, specifier: "%.1f") 公斤")
                    }
                }.listRowBackground(Studio.surface)
                Section(String(localized: "组间休息")) {
                    Stepper(value: Binding(get: { store.restSeconds }, set: { store.setRestSeconds($0) }), in: 0...600, step: 15) {
                        Text(store.restSeconds == 0 ? String(localized: "完成本组后不自动休息") : String(localized: "休息时长：\(store.restSeconds) 秒"))
                    }.accessibilityIdentifier("rest-duration")
                    Toggle(String(localized: "后台休息提醒"), isOn: Binding(get: { store.remindersEnabled }, set: { enabled in
                        Task { await store.setRemindersEnabled(enabled) }
                    }))
                    Text(String(localized: "完成一组后自动倒计时。开启通知后，锁屏或切到其他应用也能收到提醒。"))
                        .font(.footnote).foregroundStyle(Studio.muted)
                    if let message = store.reminderMessage {
                        Text(message).font(.footnote).foregroundStyle(Studio.accent)
                    }
                }.listRowBackground(Studio.surface)
                Section(String(localized: "权限与帮助")) {
                    NavigationLink(String(localized: "手表健康权限")) {
                        Form {
                            Section(String(localized: "在手表本机操作")) {
                                Text(String(localized: "设置 → 健康 → 数据来源、App 和服务 → 健身计数器"))
                                Text(String(localized: "开启「允许写入」中的「体能训练」。"))
                            }.listRowBackground(Studio.surface)
                            Section {
                                Text(String(localized: "应用也可能显示为 PowerReps。"))
                                Text(String(localized: "开启后，回到手表采集页点「检查同步权限」。"))
                            }.listRowBackground(Studio.surface)
                        }
                        .scrollContentBackground(.hidden).background(Studio.background)
                        .navigationTitle(String(localized: "手表健康权限")).navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(Studio.background, for: .navigationBar)
                    }
                }.listRowBackground(Studio.surface)
                #if GYMCOUNT_SYNC
                Section {
                    NavigationLink(String(localized: "开发者工具")) { PhoneDeveloperToolsView() }
                }.listRowBackground(Studio.surface)
                #endif
                Section {
                    LabeledContent(String(localized: "版本"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }.listRowBackground(Studio.surface)
            }.scrollContentBackground(.hidden).background(Studio.background)
                .navigationTitle(String(localized: "设置"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Studio.background, for: .navigationBar)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(0, title: String(localized: "训练"), icon: "dumbbell.fill")
            tabButton(1, title: String(localized: "历史"), icon: "clock")
            tabButton(2, title: String(localized: "设置"), icon: "gearshape")
        }.padding(.top, 5).padding(.bottom, 3)
            .background(Studio.background.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 0.5) }
    }

    private func tabButton(_ index: Int, title: String, icon: String) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 21, weight: .regular))
                Text(title).font(.system(size: 12, weight: tab == index ? .medium : .regular))
            }.foregroundStyle(tab == index ? Studio.accent : Studio.muted)
                .frame(maxWidth: .infinity, minHeight: 47)
        }.buttonStyle(.plain).accessibilityIdentifier("tab-\(index)")
            .accessibilityAddTraits(tab == index ? .isSelected : [])
    }
}

struct StudioPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.black)
            .font(Studio.button)
            .frame(maxWidth: .infinity, minHeight: Studio.buttonHeight)
            .background(Studio.accent, in: Capsule())
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
    }
}

struct StudioSecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Studio.ink)
            .font(Studio.button)
            .frame(maxWidth: .infinity, minHeight: Studio.buttonHeight)
            .background(Studio.surface, in: Capsule())
            .overlay(Capsule().stroke(Studio.accent.opacity(0.2), lineWidth: 0.5))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
    }
}
