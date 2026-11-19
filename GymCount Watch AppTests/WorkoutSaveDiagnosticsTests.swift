import Foundation
import Testing
@testable import GymCount_Watch_App

@MainActor
@Suite(.serialized)
struct WorkoutSaveDiagnosticsTests {
    @Test func recordsQueueWaitSeparatelyAndPreservesReturnAndError() async throws {
        let (entered, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let blocker = Task.detached {
            try await WorkoutFileIO.shared.perform(diagnosticPhase: "test.blocker") {
                signal.yield()
                _ = release.wait(timeout: .now() + 3)
            }
        }
        var starts = entered.makeAsyncIterator()
        try #require(await starts.next() != nil)
        Task.detached {
            try await Task.sleep(for: .milliseconds(180))
            release.signal()
        }
        let value = try await WorkoutFileIO.shared.perform(diagnosticPhase: "test.queued") { 42 }
        #expect(value == 42)
        try await blocker.value
        do {
            let _: Int = try await WorkoutFileIO.shared.perform(diagnosticPhase: "test.throw") {
                throw NSError(domain: "DiagnosticTest", code: 7, userInfo: [NSLocalizedDescriptionKey: "PRIVATE-MARKER"])
            }
            Issue.record("Expected original error")
        } catch {
            #expect((error as NSError).domain == "DiagnosticTest" && (error as NSError).code == 7)
        }
        let logger = WorkoutSaveDiagnostics.shared
        logger.flushForTesting()
        let text = try String(contentsOf: logger.directory.appendingPathComponent("workout-save-v1.jsonl"), encoding: .utf8)
        #expect(!text.contains("PRIVATE-MARKER"))
        let rows = try text.split(separator: "\n").map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        let lastOperation = try #require(rows.last { $0["phase"] as? String == "file.test.queued" }?["operation"] as? String)
        let queued = rows.filter { $0["operation"] as? String == lastOperation }
        #expect(queued.map { $0["event"] as? String } == ["begin", "running", "end"])
        let running = try #require(queued.first { $0["event"] as? String == "running" })
        #expect((running["elapsedMs"] as? Double ?? 0) >= 100)
        #expect(rows.contains { $0["phase"] as? String == "file.test.throw" && $0["outcome"] as? String == "error" && $0["errorCode"] as? Int == 7 })
    }

    @Test func boundedFilesAndUnwritableDiagnosticsDoNotChangeOperations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let logger = WorkoutSaveDiagnostics(directory: root, maximumBytes: 4096)
        for _ in 0..<120 { #expect(logger.measure("test.rotation") { 5 } == 5) }
        logger.flushForTesting()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        #expect(files.count == 2)
        for file in files { #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize! <= 4096) }
        let badPath = root.appendingPathComponent("not-a-directory")
        try Data().write(to: badPath)
        let failing = WorkoutSaveDiagnostics(directory: badPath)
        #expect(failing.measure("test.unwritable") { 42 } == 42)
        do {
            let _: Int = try failing.measure("test.original-error") { throw NSError(domain: "OriginalError", code: 19) }
            Issue.record("Expected original error")
        } catch { #expect((error as NSError).domain == "OriginalError" && (error as NSError).code == 19) }
        failing.flushForTesting()
    }

    @Test func timelineEncodingPreservesCachedBlocksAndTrimmedTail() async throws {
        let directory = FileManager.default.temporaryDirectory
        let rawPoints = (0..<700).map { CaptureSample(t: Double($0) / 40, received_t: Double($0) / 40,
            x: Double($0) / 7, y: -0.125, z: 0.1875) }
        let points = rawPoints.map { WorkoutTimeline.VectorSample(t: $0.t, x: $0.x, y: $0.y, z: $0.z) }
        let diagnostics = WorkoutDiagnostics(prepareTimeline: true)
        for start in [0, 256] { diagnostics.raw.completedAccelerationBlock?(rawPoints[start..<start+256]) }
        let date = Date(timeIntervalSinceReferenceDate: 816746641.9414942)
        let source = WorkoutSync.Record(id: UUID(), date: date, exercise: "bench_press", totalReps: 1,
            maxWeight: 70, duration: 18, activeDuration: 2, totalWeight: 70)
        for count in [700, 400, 256, 128] {
            let timeline = try WorkoutTimeline(source: source, origin: date, acceleration: Array(points.prefix(count)),
                motion: [], detectedEvents: [2], feedbackEvents: [2.1], algorithmVersion: "bench")
            let file = directory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            try diagnostics.encodedTimeline(timeline).write(to: file, options: .atomic)
            let reloaded = try JSONDecoder().decode(WorkoutTimeline.self, from: Data(contentsOf: file))
            #expect(reloaded == timeline)
        }
    }

    @Test func wholeSaveKeepsResultAndWritesRetrievableStageFile() async throws {
        let store = DataManager.shared
        try #require(store.currentSession == nil && !store.requiresDraftRecovery)
        let health = store.settings.healthKitSyncEnabled
        store.settings.healthKitSyncEnabled = false
        defer {
            store.resetCurrentWorkout()
            store.completedWholeWorkout = nil
            store.settings.healthKitSyncEnabled = health
        }
        try #require(await store.startWholeWorkout(exerciseType: .squat, weight: 50))
        let id = try #require(store.currentSession?.id)
        let previousHistory = store.workoutHistory
        defer {
            if let saved = store.workoutHistory.first(where: { $0.id == id }) { store.deleteHistoryItem(saved) }
        }
        store.addRep()
        let (entered, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let scan = Task.detached {
            try await WorkoutFileIO.shared.perform(diagnosticPhase: "test.historyScan") {
                signal.yield()
                _ = release.wait(timeout: .now() + 4)
            }
        }
        var iterator = entered.makeAsyncIterator()
        try #require(await iterator.next() != nil)
        defer { release.signal() }
        let started = ProcessInfo.processInfo.systemUptime
        try #require(await store.finishWholeWorkout())
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        print("SAVE_WITH_BUSY_SYNC_SECONDS", elapsed)
        #expect(elapsed < 1)
        release.signal()
        try await scan.value
        #expect(store.completedWholeWorkout?.totalReps == 1)
        #expect(store.workoutHistory.first(where: { $0.id == id })?.totalReps == 1)
        let historyFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchHistory/history-v1.json")
        let reloaded = try JSONDecoder().decode([WorkoutHistory].self, from: Data(contentsOf: historyFile))
        #expect(reloaded == store.workoutHistory)
        #expect(Array(reloaded.dropFirst()) == previousHistory)
        let log = WorkoutSaveDiagnostics.shared
        log.flushForTesting()
        let data = try Data(contentsOf: log.directory.appendingPathComponent("workout-save-v1.jsonl"))
        let rows = try String(decoding: data, as: UTF8.self).split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        for phase in ["workout.save", "segment.close", "motion.stop", "motion.drain", "motion.final_analysis", "motion.apply_final", "draft.persist", "timeline.build", "report.validate", "history.encode", "history.write"] {
            #expect(rows.contains { $0["phase"] as? String == phase && $0["event"] as? String == "end" })
        }
        #expect(rows.contains { $0["phase"] as? String == "workout.save" && $0["outcome"] as? String == "saved" })
    }
}
