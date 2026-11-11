import Foundation
import Testing
@testable import GymCount_Watch_App

@MainActor
@Suite(.serialized)
struct WorkoutSaveLatencyTests {
    @Test func stoppingMotionDoesNotWaitForUnrelatedFileIO() async throws {
        let (started, signal) = AsyncStream<Void>.makeStream()
        let busyFileQueue = Task.detached {
            try await WorkoutFileIO.shared.perform {
                signal.yield()
                Thread.sleep(forTimeInterval: 2)
            }
            signal.finish()
        }
        var startedEvents = started.makeAsyncIterator()
        try #require(await startedEvents.next() != nil)
        let detector = MotionDetector()
        let start = ContinuousClock.now
        await detector.stopDetectionAsync()
        let elapsed = start.duration(to: .now)
        print("Motion stop elapsed: \(elapsed)")
        try await busyFileQueue.value
        #expect(elapsed < .seconds(1), "Stopping sensors must not wait behind unrelated file operations.")
    }
}
