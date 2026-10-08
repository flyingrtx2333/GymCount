import Foundation
import Combine

@MainActor
final class PhoneWorkoutStore: ObservableObject {
    @Published private(set) var session: WorkoutSession?
    @Published private(set) var history: [WorkoutHistory] = []
    @Published private(set) var storageError: String?
    private let defaults: UserDefaults
    private let historyKey = "phone.workoutHistory"
    private let sessionKey = "phone.activeSession"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let data = defaults.data(forKey: historyKey) {
                history = try JSONDecoder().decode([WorkoutHistory].self, from: data)
            }
            if let data = defaults.data(forKey: sessionKey) {
                session = try JSONDecoder().decode(WorkoutSession.self, from: data)
            }
        } catch {
            storageError = "无法读取本地训练记录，请勿删除应用。"
        }
    }

    func start(exercise: ExerciseType, weight: Double) {
        guard session == nil, weight.isFinite, weight >= 0 else { return }
        session = WorkoutSession(exerciseType: exercise, startTime: Date(), weight: weight)
        save()
    }

    func addRep() {
        session?.addRep()
        save()
    }

    func removeRep() {
        session?.removeRep()
        save()
    }

    func finish() {
        guard var completed = session else { return }
        completed.endSession()
        history.insert(WorkoutHistory(from: completed), at: 0)
        session = nil
        save()
    }

    func deleteHistory(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            history.remove(at: index)
        }
        save()
    }

    private func save() {
        guard storageError == nil else { return }
        do {
            let historyData = try JSONEncoder().encode(history)
            let sessionData = try session.map { try JSONEncoder().encode($0) }
            defaults.set(historyData, forKey: historyKey)
            if let sessionData {
                defaults.set(sessionData, forKey: sessionKey)
            } else {
                defaults.removeObject(forKey: sessionKey)
            }
        } catch {
            storageError = "训练记录保存失败。"
        }
    }
}
