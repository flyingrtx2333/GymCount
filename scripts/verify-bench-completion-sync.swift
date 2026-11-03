import Foundation

// Run the shipping detector on real private recordings, including their actual
// delivery times. No generated motion or simulated haptic hardware is used.
@main
enum BenchCompletionReplay {
    struct Record: Decodable { let id: Int; let recording: Recording }
    struct Baseline: Decodable { let id: Int; let feedback_events: [Double]; let stream_events: [Double] }
    struct Recording: Decodable { let exercise: String; let motion_samples: [Frame]? }
    struct Frame: Decodable {
        let t: Double
        let received_t: Double?
        let gravity: BenchVector
        let user_acceleration: BenchVector
        let rotation_rate: BenchVector
        var motion: BenchMotionSample { .init(t: t, gravity: gravity, user_acceleration: user_acceleration, rotation_rate: rotation_rate) }
        var receivedAt: Double { received_t ?? t }
    }

    static func main() throws {
        let records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let baseline = try JSONDecoder().decode([Baseline].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        var summary: [[String: Any]] = []
        for record in records where record.recording.exercise == "bench_press" {
            let frames = record.recording.motion_samples ?? []
            guard let last = frames.last else { continue }
            let expected = baseline.first { $0.id == record.id }!
            let detector = BenchPressDetector()
            var completions: [BenchCycle] = []
            detector.onCompletion = { completions.append($0) }
            for frame in frames { detector.process(frame.motion, receivedAt: frame.receivedAt) }
            let live = completions
            let final = detector.finish(receivedAt: last.receivedAt)
            _ = detector.finish(receivedAt: last.receivedAt)
            precondition(completions == live, "Finish emitted a late completion")
            precondition(live.map(\.end) == expected.feedback_events, "Completion timing changed")
            precondition(final.cycles.map(\.end) == expected.stream_events, "Final V8 events changed")

            var firstRepPreserved: Bool?
            if let first = live.first {
                let prefix = BenchPressDetector()
                var liveCount = 0
                prefix.onCompletion = { _ in liveCount += 1 }
                let beforeSecond = frames.filter { $0.t <= first.end + 0.05 }
                for frame in beforeSecond { prefix.process(frame.motion, receivedAt: frame.receivedAt) }
                let result = prefix.finish(receivedAt: beforeSecond.last!.receivedAt)
                // Consumers reconcile a qualified count only, never nil -> 0.
                if let count = result.count { liveCount = count }
                firstRepPreserved = liveCount == 1
                precondition(firstRepPreserved == true, "A single completed rep disappeared at finish")
            }
            detector.resetCount()
            precondition(detector.finish(receivedAt: last.receivedAt).cycles.isEmpty, "Reset retained old cycles")
            precondition(completions == live, "Reset emitted completion feedback")
            summary.append(["id": record.id, "liveCompletionCount": live.count,
                            "finalV8Count": final.cycles.count, "status": final.status,
                            "noFinishOrResetFeedback": true, "firstRepPreserved": firstRepPreserved.map { $0 as Any } ?? NSNull(),
                            "feedbackTimesUnchanged": true, "finalV8TimesUnchanged": true])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]))
    }
}
