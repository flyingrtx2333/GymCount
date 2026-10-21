import Foundation

// Compile with the shipping BenchPressAnalysis.swift. Supply a private export
// of real records; no captured sensor data is committed to the repository.
@main
enum BenchReplay {
    struct Record: Decodable {
        let id: Int
        let recording: Recording
    }
    struct Recording: Decodable {
        let exercise: String
        let motion_samples: [ReplaySample]?
    }
    struct ReplaySample: Decodable {
        let t: Double
        let received_t: Double?
        let gravity: BenchVector
        let user_acceleration: BenchVector
        let rotation_rate: BenchVector
        var motion: BenchMotionSample {
            BenchMotionSample(t: t, gravity: gravity, user_acceleration: user_acceleration, rotation_rate: rotation_rate)
        }
        var isFresh: Bool { (0...0.25).contains((received_t ?? t) - t) }
    }
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let records = try JSONDecoder().decode([Record].self, from: data)
        var output: [[String: Any]] = []
        for record in records where record.recording.exercise == "bench_press" {
            let frames = record.recording.motion_samples ?? []
            let samples = frames.map(\.motion)
            let started = Date()
            let batch = BenchPressAnalysis.analyze(samples)
            let stream = BenchPressStream()
            let feedback = BenchPressFeedback()
            var feedbackEvents: [Double] = []
            var history: [[String: Any]] = [], previous = -1
            for (index, sample) in samples.enumerated() {
                if !frames[index].isFresh { feedback.reset() }
                if frames[index].isFresh, let t = feedback.append(sample) { feedbackEvents.append(t) }
                if let result = stream.append(sample), result.cycles.count != previous {
                    history.append(["sensor_t": sample.t, "count": result.cycles.count])
                    previous = result.cycles.count
                }
            }
            let final = stream.finish()
            // Crown reversal rotates sensor X/Y together; a real trace must keep
            // its feedback timeline. This checks coordinates, not wearable accuracy.
            let reversed = BenchPressFeedback()
            var reversedEvents: [Double] = []
            for (index, sample) in samples.enumerated() {
                if !frames[index].isFresh { reversed.reset(); continue }
                func reverse(_ v: BenchVector) -> BenchVector { BenchVector(x: -v.x, y: -v.y, z: v.z) }
                let rotated = BenchMotionSample(t: sample.t, gravity: reverse(sample.gravity),
                    user_acceleration: reverse(sample.user_acceleration), rotation_rate: reverse(sample.rotation_rate))
                if let t = reversed.append(rotated) { reversedEvents.append(t) }
            }
            precondition(reversedEvents == feedbackEvents, "Feedback changed with crown coordinates")
            feedback.reset()

            let reset = BenchPressStream()
            for sample in samples { _ = reset.append(sample) }
            reset.reset()
            guard reset.finish().cycles.isEmpty else { fatalError("Reset retained a previous set") }
            output.append(["id": record.id, "status": batch.status,
                           "stream_status": final.status,
                           "events": batch.cycles.map(\.end), "turns": batch.cycles.map(\.turn),
                           "stream_events": final.cycles.map(\.end), "history": history,
                           "feedback_events": feedbackEvents, "feedback_version": BenchPressFeedback.version,
                           "interrupted": stream.interrupted, "seconds": Date().timeIntervalSince(started)])
        }
        let encoded = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(encoded)
    }
}
