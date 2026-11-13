import Foundation
import CryptoKit

struct WorkoutMessageInbox {
    struct Entry {
        let payload: [String: Any]
        var files: [URL]
        let newestDate: Date
    }

    struct Scan {
        let entries: [Entry]
        let unreadableFiles: Int
    }

    let directory: URL
    let receiverID: String
    private let maximumFileBytes = WorkoutSync.maximumReportFileBytes + 4096
    private let maximumBatchBytes = 16 * 1024 * 1024

    /// WC removes its delivered payload after the delegate returns.
    func stage(_ payload: [String: Any]) throws {
        let records = try records(in: payload)
        let key = try identity(payload, records: records)
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        guard data.count <= maximumFileBytes else { throw WorkoutSync.Failure.invalidPayload }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(key + ".plist"),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Coalesce existing UUID-named files as well as newly staged messages.
    /// Conflicting payloads keep different identities and remain retryable.
    func pending(excluding attempted: Set<URL> = []) throws -> Scan {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return Scan(entries: [], unreadableFiles: 0)
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.pathExtension == "plist" && !attempted.contains($0) }
        var entries: [String: Entry] = [:]
        var retainedBytes = 0
        var unreadable = 0
        for file in files {
            do {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size <= maximumFileBytes else {
                    throw WorkoutSync.Failure.invalidPayload
                }
                let data = try Data(contentsOf: file)
                guard data.count <= maximumFileBytes else { throw WorkoutSync.Failure.invalidPayload }
                guard let payload = try PropertyListSerialization.propertyList(from: data,
                    format: nil) as? [String: Any] else { throw WorkoutSync.Failure.invalidPayload }
                let records = try records(in: payload)
                let key = try identity(payload, records: records)
                if var entry = entries[key] {
                    entry.files.append(file)
                    entries[key] = entry
                } else {
                    if retainedBytes + size > maximumBatchBytes { break }
                    retainedBytes += size
                    entries[key] = Entry(payload: payload, files: [file],
                                         newestDate: records.map(\.date).max()!)
                }
            } catch {
                // Retain unreadable messages, while allowing valid records through.
                unreadable += 1
            }
        }
        return Scan(entries: entries.values.sorted { $0.newestDate > $1.newestDate },
                    unreadableFiles: unreadable)
    }

    func remove(_ entry: Entry) throws {
        for file in entry.files where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func records(in payload: [String: Any]) throws -> [WorkoutSync.Record] {
        if payload["kind"] as? String == WorkoutSync.reportFileKind {
            guard payload["receiver_id"] as? String == receiverID else {
                throw WorkoutSync.Failure.invalidPayload
            }
        }
        return try WorkoutSync.decode(payload)
    }

    private func identity(_ payload: [String: Any], records: [WorkoutSync.Record]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = Data((receiverID + "/" + (payload["kind"] as? String ?? "") + "/").utf8)
        data.append(try encoder.encode(records.sorted { $0.id.uuidString < $1.id.uuidString }))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
