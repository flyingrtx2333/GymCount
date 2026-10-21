import Foundation

// Compile with the shipping BenchPressAnalysis.swift and SquatAnalysis.swift.
// Supply a private export of real recordings, never committed sensor fixtures.
@main enum SquatReplay {
    struct Record: Decodable { let id: Int; let recording: Recording }
    struct Recording: Decodable { let exercise: String; let motion_samples: [BenchMotionSample]? }
    static func main() throws {
        let records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var rows: [[String: Any]] = []
        for record in records where record.recording.exercise == "squat" {
            let model = SquatStream()
            var cycles: [SquatCycle] = []
            for sample in record.recording.motion_samples ?? [] {
                if let cycle = model.append(sample) { cycles.append(cycle) }
            }
            rows.append(["id": record.id, "version": SquatStream.version,
                         "events": cycles.map(\.end), "starts": cycles.map(\.start), "turns": cycles.map(\.turn)])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]))
    }
}
