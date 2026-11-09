import Foundation

// Replay private real recordings. Only the clock epoch is shifted; sensor values,
// intervals and delivery delays are preserved. Waiting below is actual elapsed time.
@main
enum SamplingStopReplay {
    struct Record: Decodable { let id: Int; let recording: Recording }
    struct Recording: Decodable { let exercise: String; let motion_samples: [Frame]? }
    struct Frame: Decodable {
        let t: Double
        let received_t: Double?
        let gravity: BenchVector
        let user_acceleration: BenchVector
        let rotation_rate: BenchVector
        var receivedAt: Double { received_t ?? t }
        func shifted(by offset: Double) -> BenchMotionSample {
            .init(t: t + offset, gravity: gravity, user_acceleration: user_acceleration, rotation_rate: rotation_rate)
        }
    }

    static func append(_ frames: [Frame], to detector: BenchPressDetector, offset: Double) {
        for frame in frames { detector.process(frame.shifted(by: offset), receivedAt: frame.receivedAt + offset) }
    }

    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let records = try JSONDecoder().decode([Record].self, from: data)
        var rows: [[String: Any]] = []
        var reproduced = 0, actualGaps = 0
        for record in records where record.recording.exercise == "bench_press" {
            guard let frames = record.recording.motion_samples, let last = frames.last else { continue }
            let reference = BenchPressDetector(), late = BenchPressDetector(), bounded = BenchPressDetector()
            let offset = ProcessInfo.processInfo.systemUptime - last.receivedAt
            var completions = 0
            bounded.onCompletion = { _ in completions += 1 }
            for detector in [reference, late, bounded] { append(frames, to: detector, offset: offset) }
            let stoppedAt = ProcessInfo.processInfo.systemUptime
            let baseline = reference.finish(receivedAt: stoppedAt)
            let live = completions
            if baseline.count != nil {
                // Previously, the stop caller used this later time after waiting for file I/O.
                Thread.sleep(forTimeInterval: 1.15)
                let legacy = late.finish()
                precondition(legacy.status == "insufficient_data", "Failed to reproduce the old late-finish warning")
                reproduced += 1
            }
            let result = bounded.finish(receivedAt: stoppedAt)
            precondition(result.status == baseline.status && result.cycles == baseline.cycles,
                         "Closing work changed the real recording's quality or count")
            precondition(completions == live, "Closing work emitted completion feedback")
            let maximumGap = zip(frames, frames.dropFirst()).map { $1.t - $0.t }.max() ?? 0
            if maximumGap > 0.25 {
                precondition(result.status == "insufficient_data", "A real in-recording gap was hidden")
                actualGaps += 1
            }
            rows.append(["id": record.id, "status": result.status,
                         "count": result.count.map { $0 as Any } ?? NSNull(),
                         "maximumSensorGap": maximumGap, "noStopFeedback": completions == live])
        }
        precondition(reproduced > 0 && actualGaps > 0, "Input must contain complete and interrupted real recordings")

        // No samples arrive during this wait while the run is still considered active.
        // The stop boundary is taken afterwards, so this real elapsed tail gap must remain an error.
        let full = records.first { $0.id == 19 }!.recording.motion_samples!
        let stalled = BenchPressDetector()
        append(full, to: stalled, offset: ProcessInfo.processInfo.systemUptime - full.last!.receivedAt)
        Thread.sleep(forTimeInterval: 1.15)
        precondition(stalled.finish(receivedAt: ProcessInfo.processInfo.systemUptime).status == "insufficient_data",
                     "A tail gap before stopping was hidden")
        let output: [String: Any] = ["records": rows, "legacyFalseWarningsReproduced": reproduced,
                                     "realInternalGapsRetained": actualGaps, "preStopTailGapRetained": true,
                                     "motionSamplesGenerated": false]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]))
    }
}
