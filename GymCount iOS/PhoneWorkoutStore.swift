import Foundation
import Combine
import UserNotifications

struct PhoneTrainingSet: Codable, Identifiable {
    var id = UUID()
    let exercise: ExerciseType
    let weight: Double
    let reps: Int
    var imported = false
}

struct PhoneTrainingSession: Codable, Identifiable {
    var id = UUID()
    var startTime = Date()
    var endTime: Date?
    var sets: [PhoneTrainingSet] = []
    var exercise: ExerciseType
    var weight: Double
    var reps = 0
    var restEndsAt: Date?
    // Old history contains only summaries; keep it verbatim instead of inventing sets.
    var legacySummary: WorkoutHistory?

    var totalReps: Int { legacySummary?.totalReps ?? sets.reduce(0) { $0 + $1.reps } }
    var duration: TimeInterval { legacySummary?.duration ?? max(0, (endTime ?? Date()).timeIntervalSince(startTime)) }
    var exercises: [ExerciseType] {
        if let legacySummary { return [legacySummary.exerciseType] }
        return ExerciseType.allCases.filter { exercise in sets.contains { $0.exercise == exercise } }
    }
    var volume: Double? {
        guard legacySummary == nil else { return nil }
        return sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
}

@MainActor
final class PhoneWorkoutStore: ObservableObject {
    @Published private(set) var session: PhoneTrainingSession?
    @Published private(set) var history: [PhoneTrainingSession] = []
    @Published private(set) var storageError: String?
    @Published private(set) var restSeconds = 90
    @Published private(set) var remindersEnabled = false
    @Published private(set) var reminderMessage: String?
    @Published private(set) var restFinished = false
    private let defaults: UserDefaults
    private let stateKey = "phone.training.v2"
    private let reminderID: String

    private struct State: Codable {
        var session: PhoneTrainingSession?
        var history: [PhoneTrainingSession]
        var restSeconds: Int
        var remindersEnabled: Bool
    }

    init(defaults: UserDefaults = .standard, reminderID: String = "phone.training.rest") {
        self.defaults = defaults
        self.reminderID = reminderID
        do {
            if let data = defaults.data(forKey: stateKey) {
                let state = try JSONDecoder().decode(State.self, from: data)
                session = state.session
                history = state.history
                restSeconds = state.restSeconds
                remindersEnabled = state.remindersEnabled
            } else {
                if let data = defaults.data(forKey: "phone.workoutHistory") {
                    history = try JSONDecoder().decode([WorkoutHistory].self, from: data).map { old in
                        var record = PhoneTrainingSession(id: old.id, startTime: old.date, exercise: old.exerciseType, weight: old.maxWeight)
                        record.endTime = old.date.addingTimeInterval(old.duration)
                        record.legacySummary = old
                        return record
                    }
                }
                if let data = defaults.data(forKey: "phone.activeSession") {
                    let old = try JSONDecoder().decode(WorkoutSession.self, from: data)
                    var restored = PhoneTrainingSession(id: old.id, startTime: old.startTime, exercise: old.exerciseType, weight: old.weight)
                    // Retain every original repetition weight; old sessions have no set boundaries.
                    for rep in old.repRecords {
                        if let last = restored.sets.last, last.weight == rep.weight {
                            restored.sets[restored.sets.count - 1] = PhoneTrainingSet(id: last.id, exercise: old.exerciseType, weight: last.weight, reps: last.reps + 1, imported: true)
                        } else {
                            restored.sets.append(PhoneTrainingSet(exercise: old.exerciseType, weight: rep.weight, reps: 1, imported: true))
                        }
                    }
                    session = restored
                }
                save()
            }
        } catch {
            storageError = "无法读取本地训练记录，请勿删除应用。"
        }
    }

    func lastSets(for exercise: ExerciseType) -> [PhoneTrainingSet] {
        history.first(where: { $0.sets.contains { $0.exercise == exercise && !$0.imported } })?
            .sets.filter { $0.exercise == exercise && !$0.imported } ?? []
    }

    var nextSetNumber: Int {
        guard let session else { return 1 }
        return session.sets.filter { $0.exercise == session.exercise && !$0.imported }.count + 1
    }

    var suggestedSet: PhoneTrainingSet? {
        guard let session else { return nil }
        let previous = lastSets(for: session.exercise)
        guard !previous.isEmpty else { return nil }
        return previous[min(nextSetNumber - 1, previous.count - 1)]
    }

    func start(exercise: ExerciseType, weight: Double, reuseLast: Bool = false) {
        guard storageError == nil, session == nil, validWeight(weight) else { return }
        session = PhoneTrainingSession(exercise: exercise, weight: weight)
        if reuseLast, let last = lastSets(for: exercise).first {
            session?.weight = last.weight
            session?.reps = last.reps
        }
        restFinished = false
        save()
    }

    func selectExercise(_ exercise: ExerciseType, defaultWeight: Double) {
        guard session != nil, session?.reps == 0, validWeight(defaultWeight), storageError == nil else { return }
        session?.exercise = exercise
        session?.weight = session?.sets.last(where: { $0.exercise == exercise })?.weight
            ?? lastSets(for: exercise).first?.weight ?? defaultWeight
        save()
    }

    func setWeight(_ weight: Double) {
        guard storageError == nil, validWeight(weight) else { return }
        session?.weight = weight
        save()
    }

    func setReps(_ reps: Int) {
        guard storageError == nil, (0...999).contains(reps) else { return }
        session?.reps = reps
        save()
    }

    func addRep() { setReps(min(999, (session?.reps ?? 0) + 1)) }
    func removeRep() { setReps(max(0, (session?.reps ?? 0) - 1)) }

    func reuseSuggestedSet(replacingDraft: Bool = false) {
        guard storageError == nil, session?.reps == 0 || replacingDraft, let suggestedSet else { return }
        session?.weight = suggestedSet.weight
        session?.reps = suggestedSet.reps
        save()
    }

    func completeSet() {
        guard storageError == nil, var active = session, active.reps > 0 else { return }
        active.sets.append(PhoneTrainingSet(exercise: active.exercise, weight: active.weight, reps: active.reps))
        active.reps = 0
        active.restEndsAt = restSeconds > 0 ? Date().addingTimeInterval(Double(restSeconds)) : nil
        session = active
        restFinished = false
        save()
        scheduleReminder()
    }

    func undoLastSet() {
        guard storageError == nil, var active = session, active.reps == 0,
              let last = active.sets.last, !last.imported else { return }
        active.sets.removeLast()
        active.exercise = last.exercise
        active.weight = last.weight
        active.reps = last.reps
        session = active
        skipRest()
    }

    func discardDraft() {
        setReps(0)
    }

    func checkRest(now: Date = Date()) {
        guard storageError == nil, let end = session?.restEndsAt, now >= end else { return }
        session?.restEndsAt = nil
        restFinished = true
        save()
    }

    func skipRest() {
        guard storageError == nil else { return }
        session?.restEndsAt = nil
        restFinished = false
        cancelReminder()
        save()
    }

    func setRestSeconds(_ seconds: Int) {
        guard storageError == nil, (0...600).contains(seconds) else { return }
        restSeconds = seconds
        save()
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        guard storageError == nil else { return }
        if enabled {
            do {
                remindersEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                reminderMessage = remindersEnabled ? nil : "通知未开启，可在系统设置中允许通知。"
            } catch {
                remindersEnabled = false
                reminderMessage = "无法开启提醒，请稍后重试。"
            }
        } else {
            remindersEnabled = false
            reminderMessage = nil
            cancelReminder()
        }
        save()
        if remindersEnabled { scheduleReminder() }
    }

    func finish() {
        guard storageError == nil, var completed = session else { return }
        if completed.reps > 0 {
            completed.sets.append(PhoneTrainingSet(exercise: completed.exercise, weight: completed.weight, reps: completed.reps))
        }
        guard !completed.sets.isEmpty else { return }
        completed.reps = 0
        completed.restEndsAt = nil
        completed.endTime = Date()
        history.insert(completed, at: 0)
        session = nil
        restFinished = false
        cancelReminder()
        save()
    }

    func cancelEmptyTraining() {
        guard storageError == nil, let session, session.sets.isEmpty, session.reps == 0 else { return }
        self.session = nil
        cancelReminder()
        save()
    }

    func deleteHistory(at offsets: IndexSet) {
        guard storageError == nil else { return }
        for index in offsets.sorted(by: >) where history.indices.contains(index) { history.remove(at: index) }
        save()
    }

    private func validWeight(_ weight: Double) -> Bool { weight.isFinite && (0...500).contains(weight) }

    private func save() {
        guard storageError == nil else { return }
        do {
            // Save active training and history together, retaining untouched v1 keys for recovery.
            let data = try JSONEncoder().encode(State(session: session, history: history, restSeconds: restSeconds, remindersEnabled: remindersEnabled))
            defaults.set(data, forKey: stateKey)
        } catch {
            storageError = "训练记录保存失败。"
        }
    }

    private func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [reminderID])
    }

    private func scheduleReminder() {
        cancelReminder()
        guard remindersEnabled, let end = session?.restEndsAt, end > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = "准备好后，开始下一组训练。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: reminderID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false))
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.reminderMessage = "休息提醒未能设置，请留意页面倒计时。" }
            }
        }
    }
}
