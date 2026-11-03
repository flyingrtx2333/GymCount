import Foundation
import Testing
@testable import GymCount_Watch_App

@MainActor
@Suite(.serialized)
struct SiriWorkoutIntentTests {
    @Test func missingExerciseAsksInsteadOfAssumingSquat() async throws {
        #expect(await ExerciseTypeQuery().defaultResult() == nil)
        let options = try await ExerciseTypeQuery().suggestedEntities()
        #expect(options.map(\.id) == ExerciseType.allCases.map(\.rawValue))
        #expect(try await ExerciseTypeQuery().entities(for: ["not-an-exercise"]).isEmpty)
    }

    @Test func actualIntentUsesConfiguredWeightAndProtectsActiveSession() async throws {
        let store = DataManager.shared
        try #require(store.currentSession == nil && !store.requiresDraftRecovery)
        let history = store.workoutHistory
        defer { store.resetCurrentWorkout() }
        var start = StartWorkoutIntent()
        start.exerciseType = ExerciseTypeEntity(from: .benchPress)
        start.weight = nil
        _ = try await start.perform()
        let session = try #require(store.currentSession)
        #expect(session.exerciseType == .benchPress && session.isActive)
        #expect(session.weight == store.settings.defaultWeight)
        do {
            _ = try await start.perform()
            Issue.record("A repeated request must not replace an active workout")
        } catch StartWorkoutError.alreadyActive {}
        #expect(store.currentSession?.id == session.id)
        #expect(store.workoutHistory == history)
    }

    @Test func invalidWeightCannotCreateSession() async throws {
        let store = DataManager.shared
        try #require(store.currentSession == nil)
        var start = StartWorkoutIntent()
        start.exerciseType = ExerciseTypeEntity(from: .squat)
        start.weight = -1
        do {
            _ = try await start.perform()
            Issue.record("Invalid weight must fail")
        } catch StartWorkoutError.invalidWeight {}
        #expect(store.currentSession == nil)
    }

    @Test func failedCheckpointNeverReportsStarted() async throws {
        let store = DataManager.shared
        try #require(store.currentSession == nil)
        let history = store.workoutHistory
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchHistory/current-workout-v1.json")
        try #require(!FileManager.default.fileExists(atPath: url.path))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        var start = StartWorkoutIntent()
        start.exerciseType = ExerciseTypeEntity(from: .deadlift)
        start.weight = nil
        do {
            _ = try await start.perform()
            Issue.record("Siri must not announce success when saving the draft failed")
        } catch {
            #expect((error as NSError).domain == "PowerReps.Siri")
            #expect(store.saveError != nil)
        }
        #expect(store.currentSession == nil)
        #expect(store.workoutHistory == history)
    }

    @Test func wholeWorkoutTransitionsKeepOneDraftAndDiscardWithoutHistory() async throws {
        let store = DataManager.shared
        try #require(store.currentSession == nil && !store.requiresDraftRecovery)
        let history = store.workoutHistory
        let healthEnabled = store.settings.healthKitSyncEnabled
        store.settings.healthKitSyncEnabled = false
        defer {
            store.resetCurrentWorkout()
            store.settings.healthKitSyncEnabled = healthEnabled
        }
        let draftURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchHistory/current-workout-v1.json")
        let draftStore = WatchWorkoutDraftStore(url: draftURL)

        #expect(await store.startWholeWorkout(exerciseType: .squat, weight: 70))
        let id = try #require(store.currentSession?.id)
        #expect(store.isWholeWorkout && store.currentGroupNumber == 1)
        #expect(store.currentGroupReps == 0 && store.wholeTotalReps == 0)
        #expect(try draftStore.load()?.session.wholeDraft?.id == id)

        await store.pauseWholeWorkout()
        #expect(store.isWholeWorkoutPaused)
        #expect(try draftStore.load()?.session.wholeDraft?.pausedAt != nil)
        store.addRep()
        #expect(store.wholeTotalReps == 0)
        #expect(await store.nextWholeWorkoutSet() == false)
        #expect(await store.startWholeWorkout(exerciseType: .deadlift, weight: 70) == false)

        #expect(await store.switchWholeWorkoutExercise(exerciseType: .benchPress, weight: 50))
        #expect(store.isWholeWorkoutPaused)
        #expect(store.currentSession?.id == id && store.currentSession?.exerciseType == .benchPress)
        #expect(store.currentSession?.weight == 50)
        #expect(await store.switchWholeWorkoutExercise(exerciseType: .deadlift, weight: -1) == false)
        #expect(store.currentSession?.exerciseType == .benchPress && store.currentSession?.weight == 50)

        await store.resumeWholeWorkout()
        #expect(!store.isWholeWorkoutPaused)
        let restored = try #require(draftStore.load()?.session)
        #expect(restored.id == id && restored.wholeDraft?.pauses.count == 1)
        #expect(restored.wholeDraft?.pausedAt == nil)
        #expect(store.wholeTotalReps == 0 && store.workoutHistory == history)

        store.resetCurrentWorkout()
        #expect(store.currentSession == nil && !store.isWholeWorkout)
        #expect(!FileManager.default.fileExists(atPath: draftURL.path))
        #expect(store.workoutHistory == history)
    }

    @Test func endingWithoutAnActiveWorkoutCannotCreateAReport() async throws {
        let store = DataManager.shared
        try #require(store.currentSession == nil)
        let history = store.workoutHistory
        let completed = store.completedWholeWorkout
        do {
            _ = try await StopWorkoutIntent().perform()
            Issue.record("End must fail without an active workout")
        } catch StopWorkoutError.noActiveWorkout {}
        #expect(store.workoutHistory == history)
        #expect(store.completedWholeWorkout == completed)
    }

}
