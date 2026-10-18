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
        let motion_samples: [BenchMotionSample]?
    }
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let records = try JSONDecoder().decode([Record].self, from: data)
        var output: [[String: Any]] = []
        for record in records where record.recording.exercise == "bench_press" {
            let samples = record.recording.motion_samples ?? []
            let started = Date()
            let batch = BenchPressAnalysis.analyze(samples)
            let stream = BenchPressStream()
            var history: [[String: Any]] = [], previous = -1
            for sample in samples {
                if let result = stream.append(sample), result.cycles.count != previous {
                    history.append(["sensor_t": sample.t, "count": result.cycles.count])
                    previous = result.cycles.count
                }
            }
            let final = stream.finish()
            let reset = BenchPressStream()
            for sample in samples { _ = reset.append(sample) }
            reset.reset()
            guard reset.finish().cycles.isEmpty else { fatalError("Reset retained a previous set") }
            output.append(["id": record.id, "status": batch.status,
                           "stream_status": final.status,
                           "events": batch.cycles.map(\.end), "turns": batch.cycles.map(\.turn),
                           "stream_events": final.cycles.map(\.end), "history": history,
                           "interrupted": stream.interrupted, "seconds": Date().timeIntervalSince(started)])
        }
        let encoded = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(encoded)
    }
}
