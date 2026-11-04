import Foundation

// Real, read-only recordings exercise timing/coordinate invariants. Recordings
// of other lifts are not relabeled or used as accuracy evidence for new lifts.
@main
enum VerifyUpperBodyReplay {
    struct Record: Decodable { let id: Int; let recording: Recording }
    struct Recording: Decodable { let exercise: String; let motion_samples: [BenchMotionSample]? }

    static func main() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let bytes = try Data(contentsOf: source)
        let records = try JSONDecoder().decode([Record].self, from: bytes)
        var output: [[String: Any]] = []
        for exercise in [ExerciseType.overheadPress, .barbellRow, .bicepCurl] {
            for record in records {
                let samples = record.recording.motion_samples ?? []
                guard !samples.isEmpty else { continue }
                let detector = UpperBodyDetector(exercise: exercise)!
                let reversed = UpperBodyDetector(exercise: exercise)!
                var actual: [UpperBodyCycle] = [], rotated: [UpperBodyCycle] = []
                for sample in samples {
                    if let cycle = detector.append(sample) {
                        precondition(cycle.start < cycle.end && cycle.end == sample.t)
                        precondition(actual.last.map { $0.end < cycle.start } ?? true)
                        actual.append(cycle)
                    }
                    func reverse(_ v: BenchVector) -> BenchVector { .init(x: -v.x, y: -v.y, z: v.z) }
                    let transformed = BenchMotionSample(t: sample.t, gravity: reverse(sample.gravity),
                        user_acceleration: reverse(sample.user_acceleration), rotation_rate: reverse(sample.rotation_rate))
                    if let cycle = reversed.append(transformed) { rotated.append(cycle) }
                }
                precondition(actual == rotated, "Crown coordinate reversal changed completion times")
                precondition(detector.repCount == actual.count)
                detector.resetCount()
                precondition(detector.cycles.isEmpty && !detector.interrupted)
                output.append(["sourceRecord": record.id, "sourceExercise": record.recording.exercise,
                    "selectedDetector": exercise.rawValue, "sourceFrames": samples.count,
                    "completionTimesCoordinateInvariant": true, "orderedSensorTimeWindows": true,
                    "resetClearedState": true, "matchingExerciseAccuracyEvaluated": record.recording.exercise == exercise.rawValue])
            }
        }
        let after = try Data(contentsOf: source)
        precondition(after == bytes, "Private source changed")
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]))
    }
}
