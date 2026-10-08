import SwiftUI

struct PhoneContentView: View {
    @EnvironmentObject private var store: PhoneWorkoutStore
    @AppStorage("phone.defaultWeight") private var weight = 50.0
    @State private var exercise: ExerciseType = .benchPress
    @State private var confirmingFinish = false

    private func name(_ exercise: ExerciseType) -> String {
        switch exercise {
        case .benchPress: return "卧推"
        case .squat: return "深蹲"
        case .deadlift: return "硬拉"
        }
    }

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        if let error = store.storageError {
                            Text(error).foregroundStyle(.red)
                        }
                        if let session = store.session {
                            Text(name(session.exerciseType)).font(.largeTitle.bold())
                            Text("\(session.weight, specifier: "%.1f") kg")
                                .foregroundStyle(.secondary)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(Duration.seconds(max(0, context.date.timeIntervalSince(session.startTime)))
                                    .formatted(.time(pattern: .minuteSecond)))
                                    .font(.title2.monospacedDigit())
                            }
                            Text("\(session.totalReps)")
                                .font(.system(size: 112, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .accessibilityLabel("已完成 \(session.totalReps) 次")
                            Text("完成次数").foregroundStyle(.secondary)
                            Button(action: store.addRep) {
                                Label("增加一次", systemImage: "plus")
                                    .font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 72)
                            }
                            .buttonStyle(.borderedProminent)
                            .sensoryFeedback(.increase, trigger: session.totalReps)
                            Button("撤销一次", action: store.removeRep)
                                .disabled(session.totalReps == 0)
                            Button("结束并保存") { confirmingFinish = true }
                                .buttonStyle(.bordered)
                        } else {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 56)).foregroundStyle(.tint)
                            Text("开始你的下一组").font(.title.bold())
                            Picker("训练动作", selection: $exercise) {
                                ForEach(ExerciseType.allCases, id: \.self) { item in
                                    Text(name(item)).tag(item)
                                }
                            }.pickerStyle(.segmented)
                            Stepper(value: $weight, in: 0...500, step: 2.5) {
                                Text("训练重量：\(weight, specifier: "%.1f") kg")
                            }
                            Button("开始训练") { store.start(exercise: exercise, weight: weight) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(store.storageError != nil)
                        }
                        Text("iPhone 首版采用手动计数，不需要拿着手机完成动作。记录仅保存在本机，暂不与 Apple Watch 同步。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(24)
                }
                .navigationTitle("GymCount")
                .confirmationDialog("结束当前训练并保存记录？", isPresented: $confirmingFinish, titleVisibility: .visible) {
                    Button("结束并保存", action: store.finish)
                    Button("继续训练", role: .cancel) {}
                }
            }.tabItem { Label("训练", systemImage: "dumbbell") }
            NavigationStack {
                List {
                    ForEach(store.history) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(name(item.exerciseType)).font(.headline)
                                Spacer()
                                Text("\(item.totalReps) 次").font(.headline)
                            }
                            Text(item.date, format: .dateTime.month().day().hour().minute())
                            Text("\(item.maxWeight, specifier: "%.1f") kg · \(Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)))")
                        }.foregroundStyle(.secondary)
                    }.onDelete(perform: store.deleteHistory)
                }
                .overlay {
                    if store.history.isEmpty {
                        ContentUnavailableView("还没有训练记录", systemImage: "clock", description: Text("结束训练后，记录会显示在这里。"))
                    }
                }
                .navigationTitle("训练记录")
                .toolbar { EditButton() }
            }.tabItem { Label("历史", systemImage: "clock") }
        }
    }
}
