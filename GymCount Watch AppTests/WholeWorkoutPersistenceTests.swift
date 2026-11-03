import Foundation
import Testing
@testable import GymCount_Watch_App

/// The isolated app is seeded externally with a report replayed from actual
/// captured training. This test creates no repetitions or HealthKit values.
@MainActor
@Suite(.serialized)
struct WholeWorkoutPersistenceTests {
    @Test func saveRecoveredActualReport() async throws {
        let store = DataManager.shared
        try #require(store.requiresWorkoutRecovery && store.isWholeWorkout)
        let session = try #require(store.currentSession)
        let draft = try #require(session.wholeDraft)
        let expected = try #require(draft.pendingReport)
        try #require(session.endTime != nil && expected.totalReps > 0)
        try expected.validate()

        let before = store.workoutHistory
        try #require(!before.contains { $0.id == draft.id }, "The isolated replay must not overwrite an existing history record")
        defer {
            if let inserted = store.workoutHistory.first(where: { $0.id == draft.id }) {
                store.deleteHistoryItem(inserted)
            }
            store.completedWholeWorkout = nil
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchHistory")
        let historyURL = folder.appendingPathComponent("history-v1.json")
        let draftURL = folder.appendingPathComponent("current-workout-v1.json")

        #expect(await store.finishWholeWorkout())
        let saved = try #require(store.workoutHistory.first { $0.id == draft.id })
        #expect(saved.workoutReport == expected)
        #expect(saved.date == expected.startedAt)
        #expect(saved.totalReps == expected.totalReps)
        #expect(saved.maxWeight == expected.maxWeight)
        #expect(saved.totalWeight == expected.totalWeight)
        #expect(saved.duration == expected.duration)
        #expect(saved.activeDuration == expected.activeDuration)
        #expect(store.workoutHistory.count == before.count + 1)
        #expect(store.currentSession == nil && !store.requiresWorkoutRecovery)
        #expect(store.completedWholeWorkout == expected)
        #expect(!FileManager.default.fileExists(atPath: draftURL.path))

        let persisted = try JSONDecoder().decode([WorkoutHistory].self, from: Data(contentsOf: historyURL))
        #expect(persisted == store.workoutHistory)
        #expect(persisted.first { $0.id == draft.id }?.workoutReport == expected)

        store.deleteHistoryItem(saved)
        #expect(store.workoutHistory == before)
        let restored = try JSONDecoder().decode([WorkoutHistory].self, from: Data(contentsOf: historyURL))
        #expect(restored == before)
    }
}
