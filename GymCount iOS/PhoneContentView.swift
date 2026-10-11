import SwiftUI

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
    @AppStorage("phone.defaultWeight") private var weight = 50.0
    @State private var exercise: ExerciseType = .benchPress
    @State private var tab = 0
    @State private var confirmingFinish = false
    @State private var historyEditMode: EditMode = .inactive

    private func name(_ exercise: ExerciseType) -> String {
        switch exercise {
        case .benchPress: return "卧推"
        case .squat: return "深蹲"
        case .deadlift: return "硬拉"
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
    }

    private var training: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text("训练").font(Studio.title)
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
            .confirmationDialog("结束当前训练并保存记录？", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("结束并保存", action: store.finish)
                Button("继续训练", role: .cancel) {}
            }
        }
    }

    private var readyTraining: some View {
        VStack(spacing: 0) {
            Text("开始下一组")
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
                weightButton("减少重量", symbol: "minus", disabled: weight <= 0) { weight = max(0, weight - 2.5) }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(weight, format: .number.precision(.fractionLength(0...1)))
                        .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.65)
                    Text("公斤").font(.system(size: 17)).foregroundStyle(Studio.muted)
                }.accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                weightButton("增加重量", symbol: "plus", disabled: weight >= 500) { weight = min(500, weight + 2.5) }
            }
            .padding(.horizontal, 24).padding(.bottom, 14)
            Button { store.start(exercise: exercise, weight: weight) } label: {
                Text("开始训练")
            }.buttonStyle(StudioPrimaryButton()).disabled(store.storageError != nil)
                .padding(.top, 10).padding(.bottom, 33)
            Rectangle().fill(Studio.line).frame(height: 0.5)
            Button { tab = 1 } label: {
                VStack(spacing: 10) {
                    Image(systemName: "clock").font(.system(size: 25, weight: .light))
                        .foregroundStyle(Studio.muted)
                    if let latest = store.history.first {
                        Text("最近训练 · \(name(latest.exerciseType)) · \(latest.totalReps) 次")
                            .font(.system(size: 15)).foregroundStyle(Studio.muted)
                    } else {
                        Text("还没有训练记录").font(.system(size: 15)).foregroundStyle(Studio.muted)
                    }
                    HStack(spacing: 8) {
                        Text("查看历史")
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

    private func activeTraining(_ session: WorkoutSession) -> some View {
        VStack(spacing: 14) {
            exerciseImage(session.exerciseType, size: 92)
            Text(name(session.exerciseType)).font(.system(size: 30, weight: .bold))
            HStack(spacing: 16) {
                Text("\(session.weight, specifier: "%.1f") 公斤")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(max(0, context.date.timeIntervalSince(session.startTime)))
                        .formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                }
            }.font(.system(size: 17)).foregroundStyle(Studio.muted)
            Text("\(session.totalReps)").font(.system(size: 92, weight: .semibold, design: .rounded)).monospacedDigit()
                .accessibilityLabel("已完成 \(session.totalReps) 次")
            Text("完成次数").font(.system(size: 15)).foregroundStyle(Studio.muted)
            Button(action: store.addRep) {
                Label("增加一次", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(StudioPrimaryButton()).sensoryFeedback(.increase, trigger: session.totalReps)
            Button("撤销一次", action: store.removeRep).disabled(session.totalReps == 0)
                .frame(minHeight: 44)
            Button("结束并保存") { confirmingFinish = true }
                .buttonStyle(StudioSecondaryButton())
        }
    }

    private var history: some View {
        NavigationStack {
            List {
                ForEach(store.history) { item in
                    HStack(spacing: 16) {
                        exerciseImage(item.exerciseType, size: 54)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(name(item.exerciseType)).font(.headline)
                                Spacer()
                                Text("\(item.totalReps) 次").font(.headline).foregroundStyle(Studio.accent)
                            }
                            Text(item.date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))
                            Text("\(item.maxWeight, specifier: "%.1f") 公斤 · \(Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)))")
                        }.font(.subheadline)
                    }.listRowBackground(Studio.surface).listRowSeparatorTint(Studio.line)
                }.onDelete(perform: store.deleteHistory)
            }
            .scrollContentBackground(.hidden).background(Studio.background)
            .overlay {
                if store.history.isEmpty {
                    ContentUnavailableView("还没有训练记录", systemImage: "clock")
                }
            }
            .navigationTitle("训练记录")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $historyEditMode)
            .toolbar {
                Button(historyEditMode == .active ? "完成" : "编辑") {
                    withAnimation { historyEditMode = historyEditMode == .active ? .inactive : .active }
                }
            }
            .toolbarBackground(Studio.background, for: .navigationBar)
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("训练偏好") {
                    Stepper(value: $weight, in: 0...500, step: 2.5) {
                        Text("默认重量：\(weight, specifier: "%.1f") 公斤")
                    }
                }.listRowBackground(Studio.surface)
                Section("权限与帮助") {
                    NavigationLink("手表健康权限") {
                        Form {
                            Section("在手表本机操作") {
                                Text("设置 → 健康 → 数据来源、App 和服务 → 健身计数器")
                                Text("开启「允许写入」中的「体能训练」。")
                            }.listRowBackground(Studio.surface)
                            Section {
                                Text("应用也可能显示为 PowerReps。")
                                Text("开启后，回到手表采集页点「检查同步权限」。")
                            }.listRowBackground(Studio.surface)
                        }
                        .scrollContentBackground(.hidden).background(Studio.background)
                        .navigationTitle("手表健康权限").navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(Studio.background, for: .navigationBar)
                    }
                }.listRowBackground(Studio.surface)
                #if GYMCOUNT_SYNC
                Section {
                    NavigationLink("开发者工具") { PhoneDeveloperToolsView() }
                }.listRowBackground(Studio.surface)
                #endif
                Section {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }.listRowBackground(Studio.surface)
            }.scrollContentBackground(.hidden).background(Studio.background)
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Studio.background, for: .navigationBar)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(0, title: "训练", icon: "dumbbell.fill")
            tabButton(1, title: "历史", icon: "clock")
            tabButton(2, title: "设置", icon: "gearshape")
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
