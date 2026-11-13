import Foundation
import Combine

// Supply a read-only phone snapshot and its delivered WC inbox. All mutations
// below use temporary copies, including deliberate failure/conflict cases.
@main enum VerifyWorkoutInbox {
    @MainActor static func main() async throws {
        guard (3...4).contains(CommandLine.arguments.count) else { throw WorkoutSync.Failure.invalidPayload }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let sourceInbox = URL(fileURLWithPath: CommandLine.arguments[2])
        let original = try Data(contentsOf: source)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PowerReps.InboxCheck." + UUID().uuidString)
        let suite = "PowerReps.InboxCheck." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let snapshot = root.appendingPathComponent("records-v3.json")
        try original.write(to: snapshot)
        let sourceTimelines = source.deletingLastPathComponent().appendingPathComponent("Timelines")
        if FileManager.default.fileExists(atPath: sourceTimelines.path) {
            try FileManager.default.copyItem(at: sourceTimelines, to: root.appendingPathComponent("Timelines"))
        }
        let delivered = try FileManager.default.contentsOfDirectory(at: sourceInbox, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "plist" }
        let first = try PropertyListSerialization.propertyList(from: Data(contentsOf: delivered[0]), format: nil) as! [String: Any]
        let receiver = first["receiver_id"] as! String
        let inbox = WorkoutMessageInbox(directory: root.appendingPathComponent("IncomingWorkouts"), receiverID: receiver)
        try FileManager.default.copyItem(at: sourceInbox, to: inbox.directory)
        let scanStarted = ContinuousClock.now
        let pending = try inbox.pending()
        let scanTime = scanStarted.duration(to: .now)
        precondition(pending.unreadableFiles == 0 && !pending.entries.isEmpty)
        precondition(pending.entries.reduce(0) { $0 + $1.files.count } == delivered.count)
        precondition(pending.entries.map(\.newestDate) == pending.entries.map(\.newestDate).sorted(by: >))
        let allRecords = try pending.entries.flatMap { try WorkoutSync.decode($0.payload) }
        func open() -> PhoneWorkoutStore {
            PhoneWorkoutStore(defaults: defaults, reminderID: suite,
                watchArchiveURL: root.appendingPathComponent("watch.json"), snapshotURL: snapshot)
        }
        let store = open()
        precondition(!store.requiresRecovery)
        let initialCount = store.history.count
        let originalIDs = Set(store.history.map(\.id))
        let snapshotState = try JSONDecoder().decode(RecordSnapshot.self, from: original)
        let missing = Set(allRecords.map(\.id)).subtracting(originalIDs).subtracting(snapshotState.deletedIDs)
        for entry in pending.entries {
            // The production receiver removes files only after this durable save.
            try await store.receiveWatchHistory(WorkoutSync.decode(entry.payload))
            let durable = try JSONDecoder().decode(RecordSnapshot.self, from: Data(contentsOf: snapshot))
            for record in try WorkoutSync.decode(entry.payload) {
                precondition(durable.deletedIDs.contains(record.id) || durable.history.contains { $0.id == record.id })
            }
            try inbox.remove(entry)
        }
        let drained = try inbox.pending()
        precondition(drained.entries.isEmpty)
        precondition(store.history.count == initialCount + missing.count)
        precondition(open().history == store.history, "Relaunch lost accepted records")
        if CommandLine.arguments.count == 4 {
            try Data(contentsOf: snapshot).write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
        }

        // Duplicate deliveries validate their source without rewriting a durable
        // snapshot or invalidating every records/trends view observing the store.
        let beforeRetry = try Data(contentsOf: snapshot)
        let modified = try snapshot.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let revision = store.historyRevision
        var notifications = 0
        let observer = store.objectWillChange.sink { notifications += 1 }
        for entry in pending.entries { try await store.receiveWatchHistory(WorkoutSync.decode(entry.payload)) }
        observer.cancel()
        let afterRetry = try Data(contentsOf: snapshot)
        let modifiedAfter = try snapshot.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        precondition(notifications == 0 && store.historyRevision == revision)
        precondition(beforeRetry == afterRetry && modified == modifiedAfter)
        // A missing durable snapshot must still be recreated before a receipt.
        try FileManager.default.removeItem(at: snapshot)
        try await store.receiveWatchHistory(WorkoutSync.decode(pending.entries[0].payload))
        precondition(open().history == store.history)

        // New retries, including differently ordered JSON, share one inbox file.
        for entry in pending.entries {
            for _ in 0..<3 {
                var reordered = entry.payload
                let json = try JSONSerialization.jsonObject(with: reordered["payload"] as! Data)
                reordered["payload"] = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
                try inbox.stage(reordered)
            }
        }
        let deduplicated = try inbox.pending()
        precondition(deduplicated.entries.count == pending.entries.count)
        precondition(deduplicated.entries.allSatisfy { $0.files.count == 1 })

        // Local corrections and deletion marks remain authoritative on replay.
        let existing = store.history.first { $0.watchSummary != nil && $0.totalReps < 1_000_000 }!
        let correctedReps = existing.totalReps + 1
        precondition(store.updateRecord(id: existing.id, date: existing.startTime, sets: [], duration: nil,
            summaryReps: correctedReps, summaryWeight: existing.maxWeight, note: "inbox verification"))
        let deleted = allRecords.first { $0.id != existing.id }!.id
        precondition(store.deleteRecords(ids: [deleted]))
        for entry in deduplicated.entries {
            try await store.receiveWatchHistory(WorkoutSync.decode(entry.payload))
            try inbox.remove(entry)
        }
        let reopened = open()
        precondition(reopened.history.first { $0.id == existing.id }?.totalReps == correctedReps)
        precondition(reopened.history.first { $0.id == existing.id }?.note == "inbox verification")
        precondition(!reopened.history.contains { $0.id == deleted })

        // Invalid/cross-install messages cannot prevent valid entries draining.
        let validEntry = pending.entries[0]
        try inbox.stage(validEntry.payload)
        try Data("broken plist".utf8).write(to: inbox.directory.appendingPathComponent("broken.plist"))
        var foreign = validEntry.payload; foreign["receiver_id"] = UUID().uuidString
        do { try inbox.stage(foreign); preconditionFailure("Foreign receiver accepted") }
        catch WorkoutSync.Failure.invalidPayload {}
        let mixed = try inbox.pending()
        precondition(mixed.entries.count == 1 && mixed.unreadableFiles == 1)
        // A failed persistence attempt must leave its delivered files retryable.
        let beforeFailure = try Data(contentsOf: mixed.entries[0].files[0])
        let blockedRoot = root.appendingPathComponent("blocked")
        let blockedSnapshot = blockedRoot.appendingPathComponent("records-v3.json")
        let blocked = PhoneWorkoutStore(defaults: defaults, reminderID: suite,
            watchArchiveURL: blockedRoot.appendingPathComponent("watch.json"), snapshotURL: blockedSnapshot)
        try? FileManager.default.removeItem(at: blockedRoot)
        try Data().write(to: blockedRoot)
        do {
            try await blocked.receiveWatchHistory(WorkoutSync.decode(validEntry.payload))
            preconditionFailure("Saving through a file succeeded")
        } catch {}
        let afterFailure = try Data(contentsOf: mixed.entries[0].files[0])
        precondition(beforeFailure == afterFailure)
        let sourceAfter = try Data(contentsOf: source)
        precondition(sourceAfter == original)
        let result: [String: Any] = ["deliveredFiles": delivered.count, "uniqueMessages": pending.entries.count,
            "initialRecords": initialCount, "recoveredRecords": missing.count, "mergedRecords": initialCount + missing.count,
            "scanTime": String(describing: scanTime), "newestFirst": true, "canonicalRetryDeduplication": true,
            "durableBeforeRemoval": true, "restartPreserved": true, "correctionsAndDeletionsPreserved": true,
            "invalidMessageDoesNotBlockValid": true, "failedSaveRetainsInbox": true, "sourceUnchanged": true,
            "duplicateViewNotifications": notifications, "duplicateSnapshotWriteSkipped": true,
            "missingSnapshotRecreatedBeforeReceipt": true]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
