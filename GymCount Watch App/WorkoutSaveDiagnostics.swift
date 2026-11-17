import Foundation

/// Timing only. Best-effort logging must never participate in workout persistence.
final class WorkoutSaveDiagnostics: @unchecked Sendable {
    static let shared = WorkoutSaveDiagnostics(directory: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics"))

    struct Span: Sendable {
        fileprivate let writer: WorkoutSaveDiagnostics
        fileprivate let id: String
        fileprivate let phase: String
        fileprivate let started: Double

        func running() { writer.record(self, event: "running") }
        func end(outcome: String = "ok", error: Error? = nil) {
            writer.record(self, event: "end", outcome: outcome, error: error)
        }
    }

    private struct Entry: Encodable, Sendable {
        let version = 1
        let timestamp: Double
        let uptime: Double
        let run: String
        let build: String
        let operation: String
        let phase: String
        let event: String
        let elapsedMs: Double
        let outcome: String?
        let errorDomain: String?
        let errorCode: Int?
        let droppedBefore: Int
    }

    let directory: URL
    private let maximumBytes: Int
    private let run = UUID().uuidString
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    private let queue = DispatchQueue(label: "PowerReps.save-diagnostics", qos: .utility)
    private let lock = NSLock()
    private var pending = 0
    private var dropped = 0

    init(directory: URL, maximumBytes: Int = 256 * 1024) {
        self.directory = directory
        self.maximumBytes = max(4096, maximumBytes)
    }

    func begin(_ phase: String) -> Span {
        let span = Span(writer: self, id: UUID().uuidString, phase: Self.label(phase),
                        started: ProcessInfo.processInfo.systemUptime)
        record(span, event: "begin")
        return span
    }

    func measure<T>(_ phase: String, _ operation: () throws -> T) rethrows -> T {
        let span = begin(phase)
        do {
            let value = try operation()
            span.end()
            return value
        } catch {
            span.end(outcome: "error", error: error)
            throw error
        }
    }

    private func record(_ span: Span, event: String, outcome: String? = nil, error: Error? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard pending < 512 else {
            if dropped < Int.max { dropped += 1 }
            lock.unlock()
            return
        }
        pending += 1
        let droppedBefore = dropped
        dropped = 0
        lock.unlock()
        let failure = error.map { $0 as NSError }
        let entry = Entry(timestamp: Date().timeIntervalSince1970, uptime: now, run: run, build: build,
            operation: span.id, phase: span.phase, event: event, elapsedMs: max(0, now - span.started) * 1000,
            outcome: outcome.map(Self.label), errorDomain: failure.map { Self.label($0.domain) }, errorCode: failure?.code,
            droppedBefore: droppedBefore)
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            // Deliberately ignore diagnostic failures, including full/unwritable storage.
            try? append(entry)
        }
    }

    private func append(_ entry: Entry) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let current = directory.appendingPathComponent("workout-save-v1.jsonl")
        let previous = directory.appendingPathComponent("workout-save-v1.previous.jsonl")
        var data = try JSONEncoder().encode(entry)
        data.append(0x0A)
        let size = (try? fm.attributesOfItem(atPath: current.path)[.size] as? NSNumber)?.intValue ?? 0
        if size + data.count > maximumBytes, fm.fileExists(atPath: current.path) {
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
            try fm.moveItem(at: current, to: previous)
        }
        if !fm.fileExists(atPath: current.path) {
            try data.write(to: current, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else {
            let handle = try FileHandle(forWritingTo: current)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }

    private static func label(_ value: String) -> String {
        String(value.prefix(96).map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-(): ".contains($0)) ? $0 : "_" })
    }

    #if DEBUG
    func flushForTesting() { queue.sync {} }
    #endif
}
