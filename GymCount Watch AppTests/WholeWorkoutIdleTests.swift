import Foundation
import Testing
@testable import GymCount_Watch_App

@MainActor
@Suite(.serialized)
struct WholeWorkoutIdleTests {
    @Test func continuingClearsWarningAndTimeoutSavesBothSets() async throws {
        let store = DataManager.shared
        try #require(store.currentSession == nil && !store.requiresDraftRecovery)
        let healthEnabled = store.settings.healthKitSyncEnabled
        store.settings.healthKitSyncEnabled = false
        defer {
            store.resetCurrentWorkout()
            store.completedWholeWorkout = nil
            store.settings.healthKitSyncEnabled = healthEnabled
        }

        try #require(await store.startWholeWorkout(exerciseType: .squat, weight: 70))
        store.addRep()
        try #require(await store.nextWholeWorkoutSet())
        store.addRep()
        let session = try #require(store.currentSession)
        let lastRep = try #require(session.repRecords.last?.timestamp)
        defer {
            if let saved = store.workoutHistory.first(where: { $0.id == session.id }) {
                store.deleteHistoryItem(saved)
            }
        }

        await store.checkWholeWorkoutIdle(at: lastRep.addingTimeInterval(299))
        #expect(!store.wholeWorkoutIdlePrompt)
        await store.checkWholeWorkoutIdle(at: lastRep.addingTimeInterval(301))
        #expect(store.wholeWorkoutIdlePrompt)
        store.continueWholeWorkoutAfterIdle()
        #expect(!store.wholeWorkoutIdlePrompt)
        store.addRep()
        let latestRep = try #require(store.currentSession?.repRecords.last?.timestamp)
        await store.checkWholeWorkoutIdle(at: latestRep.addingTimeInterval(599))
        #expect(store.currentSession?.id == session.id)
        #expect(store.wholeWorkoutIdlePrompt)
        store.addRep()
        #expect(!store.wholeWorkoutIdlePrompt)
        let endOfLastSet = try #require(store.currentSession?.repRecords.last?.timestamp)
        // Ensure the saved end comes from the last rep, even if saving happens later.
        try await Task.sleep(for: .milliseconds(500))
        await store.checkWholeWorkoutIdle(at: endOfLastSet.addingTimeInterval(600))
        let saved = try #require(store.workoutHistory.first { $0.id == session.id })
        let report = try #require(saved.workoutReport)
        #expect(store.currentSession == nil && store.wholeWorkoutEndedAfterIdle)
        #expect(report.sets.map(\.totalReps) == [1, 3])
        #expect(report.endedAt.timeIntervalSince(endOfLastSet) >= 0)
        #expect(report.endedAt.timeIntervalSince(endOfLastSet) < 0.5)
        #expect(store.completedWholeWorkout == report)
        try report.validate()

        await store.checkWholeWorkoutIdle(at: .distantFuture)
        #expect(store.workoutHistory.filter { $0.id == session.id }.count == 1)
    }

    @Test func pausedWorkoutWaitsAndEmptyTimeoutDoesNotCreateHistory() async throws {
        let store = DataManager.shared
        try #require(store.currentSession == nil && !store.requiresDraftRecovery)
        let healthEnabled = store.settings.healthKitSyncEnabled
        let before = store.workoutHistory
        store.settings.healthKitSyncEnabled = false
        defer {
            store.resetCurrentWorkout()
            store.settings.healthKitSyncEnabled = healthEnabled
        }

        try #require(await store.startWholeWorkout(exerciseType: .benchPress, weight: 50))
        await store.pauseWholeWorkout()
        await store.checkWholeWorkoutIdle(at: Date().addingTimeInterval(660))
        #expect(store.isWholeWorkoutPaused && !store.wholeWorkoutIdlePrompt)
        await store.resumeWholeWorkout()
        await store.checkWholeWorkoutIdle()
        #expect(store.currentSession != nil && !store.wholeWorkoutIdlePrompt)
        await store.checkWholeWorkoutIdle(at: Date().addingTimeInterval(601))
        #expect(store.currentSession == nil)
        #expect(store.workoutHistory == before)
        #expect(store.completedWholeWorkout == nil)
    }
}
