import Foundation
import Combine
import UserNotifications

struct PhoneTrainingSet: Codable, Identifiable {
    var id = UUID()
    let exercise: ExerciseType
    let weight: Double
    let reps: Int
    var imported = false
}

struct PhoneTrainingSession: Codable, Identifiable {
    struct Correction: Codable {
        var reps: Int
        var weight: Double
    }
    var id = UUID()
    var startTime = Date()
    var endTime: Date?
    var sets: [PhoneTrainingSet] = []
    var exercise: ExerciseType
    var weight: Double
    var reps = 0
    var restEndsAt: Date?
    // Old history contains only summaries; keep it verbatim instead of inventing sets.
    var legacySummary: WorkoutHistory?
    var watchSummary: WorkoutHistory?
    var correction: Correction?
    var manualEntry: Bool?
    var note: String?
    var recordedDuration: TimeInterval?
    private var summary: WorkoutHistory? { watchSummary ?? legacySummary }

    var totalReps: Int { correction?.reps ?? summary?.totalReps ?? sets.reduce(0) { $0 + $1.reps } }
    var maxWeight: Double { correction?.weight ?? summary?.maxWeight ?? sets.map(\.weight).max() ?? weight }
    var isSummary: Bool { summary != nil }
    var displayDuration: TimeInterval? { manualEntry == true ? recordedDuration : duration }
    var duration: TimeInterval { summary?.duration ?? max(0, (endTime ?? Date()).timeIntervalSince(startTime)) }
    var activeDuration: TimeInterval? { summary?.activeDuration }
    var exercises: [ExerciseType] {
        if let summary { return [summary.exerciseType] }
        return ExerciseType.allCases.filter { exercise in sets.contains { $0.exercise == exercise } }
    }
    var volume: Double? {
        guard summary == nil else { return nil }
        return sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
}

// Editable text is preserved verbatim so unfinished fields survive relaunch.
struct RecordSetDraft: Codable, Identifiable, Hashable {
    var id = UUID()
    var exercise: ExerciseType
    var weight = ""
    var reps = ""
    var imported = false
    init(exercise: ExerciseType, weight: String = "") { self.exercise = exercise; self.weight = weight }
    init(_ set: PhoneTrainingSet) {
        id = set.id; exercise = set.exercise; weight = set.weight.formatted(.number.grouping(.never)); reps = String(set.reps); imported = set.imported
    }
    var parsed: PhoneTrainingSet? {
        guard let weight = Double(weight.replacingOccurrences(of: ",", with: ".")), weight.isFinite,
              (0...500).contains(weight), let reps = Int(reps), (1...999).contains(reps) else { return nil }
        return PhoneTrainingSet(id: id, exercise: exercise, weight: weight, reps: reps, imported: imported)
    }
}

struct RecordEditorDraft: Codable, Identifiable, Hashable {
    var id = UUID()
    var recordID: UUID?
    var date = Date()
    var sets: [RecordSetDraft]
    var duration = ""
    var summaryReps = ""
    var summaryWeight = ""
    var note = ""
}

struct RecordSnapshot: Codable {
    var version = 3
    var session: PhoneTrainingSession?
    var history: [PhoneTrainingSession] = []
    var deletedIDs: Set<UUID> = []
    var editorDrafts: [RecordEditorDraft] = []
    var lastExercise: ExerciseType = .benchPress
    var lastWeight: Double?
    var lastSyncAt: Date?
}

struct RecordBackup: Codable {
    var format = "com.flyingrtx.powerreps.records"
    var version = 1
    var createdAt = Date()
    var snapshot: RecordSnapshot
}

struct RecordRestorePreview: Identifiable {
    let id = UUID()
    let backup: RecordBackup
    let added: Int
    let skipped: Int
    let drafts: Int
}

enum RecordFileError: LocalizedError {
    case invalid, unsupported, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: return String(localized: "备份文件损坏或内容无效")
        case .unsupported: return String(localized: "不支持此备份版本")
        case .unavailable: return String(localized: "记录未能保存，请重试")
        }
    }
}

@MainActor
final class PhoneWorkoutStore: ObservableObject {
    @Published private var state = RecordSnapshot()
    @Published private(set) var storageError: String?
    private var readable = true
    let snapshotURL: URL
    private let defaults: UserDefaults
    private let reminderID: String
    var history: [PhoneTrainingSession] { state.history }
    var session: PhoneTrainingSession? { state.session }
    var editorDrafts: [RecordEditorDraft] { state.editorDrafts }
    var lastExercise: ExerciseType { state.lastExercise }
    var lastWeight: Double? { state.lastWeight }
    var lastSyncAt: Date? { state.lastSyncAt }

    private struct LegacyState: Codable {
        var session: PhoneTrainingSession?
        var history: [PhoneTrainingSession]
        var restSeconds: Int
        var remindersEnabled: Bool
    }

    init(defaults: UserDefaults = .standard, reminderID: String = "phone.training.rest", watchArchiveURL: URL? = nil, snapshotURL: URL? = nil) {
        self.defaults = defaults; self.reminderID = reminderID
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.snapshotURL = snapshotURL ?? watchArchiveURL?.deletingLastPathComponent().appendingPathComponent("records-v3.json")
            ?? support.appendingPathComponent("Records/records-v3.json")
        do {
            if FileManager.default.fileExists(atPath: self.snapshotURL.path) {
                let decoded = try JSONDecoder().decode(RecordSnapshot.self, from: Data(contentsOf: self.snapshotURL))
                try Self.validate(decoded)
                state = decoded
            } else {
                var next = RecordSnapshot()
                if let data = defaults.data(forKey: "phone.training.v2") {
                    let old = try JSONDecoder().decode(LegacyState.self, from: data)
                    next.history = old.history; next.session = old.session
                } else {
                    if let data = defaults.data(forKey: "phone.workoutHistory") {
                        next.history = try JSONDecoder().decode([WorkoutHistory].self, from: data).map { old in
                            var item = PhoneTrainingSession(id: old.id, startTime: old.date, exercise: old.exerciseType, weight: old.maxWeight)
                            item.endTime = old.date.addingTimeInterval(old.duration); item.legacySummary = old
                            return item
                        }
                    }
                    if let data = defaults.data(forKey: "phone.activeSession") {
                        let old = try JSONDecoder().decode(WorkoutSession.self, from: data)
                        var item = PhoneTrainingSession(id: old.id, startTime: old.startTime, exercise: old.exerciseType, weight: old.weight)
                        for rep in old.repRecords {
                            if let last = item.sets.last, last.weight == rep.weight {
                                item.sets[item.sets.count - 1] = PhoneTrainingSet(id: last.id, exercise: old.exerciseType, weight: rep.weight, reps: last.reps + 1, imported: true)
                            } else { item.sets.append(PhoneTrainingSet(exercise: old.exerciseType, weight: rep.weight, reps: 1, imported: true)) }
                        }
                        next.session = item
                    }
                }
                let archive = try WatchWorkoutArchive(url: watchArchiveURL ?? support.appendingPathComponent("WatchWorkouts/history.json"))
                next.deletedIDs = archive.deletedIDs
                next.history.removeAll { next.deletedIDs.contains($0.id) }
                try Self.merge(archive.records, into: &next, allowLegacy: true)
                try Self.validate(next)
                try Self.write(next, to: self.snapshotURL)
                state = next
            }
        } catch {
            readable = false
            storageError = String(localized: "无法读取本地训练记录，请勿删除应用。")
        }
    }

    private static func write(_ snapshot: RecordSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    @discardableResult
    private func commit(_ next: RecordSnapshot) -> Bool {
        guard readable else { return false }
        do {
            try Self.validate(next)
            try Self.write(next, to: snapshotURL)
            state = next; storageError = nil
            return true
        } catch {
            storageError = String(localized: "记录未能保存，请重试")
            return false
        }
    }

    static func validate(_ snapshot: RecordSnapshot) throws {
        guard snapshot.version == 3 else { throw RecordFileError.unsupported }
        guard snapshot.history.count <= 100_000, Set(snapshot.history.map(\.id)).count == snapshot.history.count,
              snapshot.deletedIDs.isDisjoint(with: snapshot.history.map(\.id)),
              snapshot.editorDrafts.count <= 500, Set(snapshot.editorDrafts.map(\.id)).count == snapshot.editorDrafts.count,
              snapshot.lastWeight.map({ $0.isFinite && $0 >= 0 }) ?? true,
              snapshot.lastSyncAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw RecordFileError.invalid }
        for record in snapshot.history + (snapshot.session.map { [$0] } ?? []) {
            guard record.startTime.timeIntervalSince1970.isFinite, record.weight.isFinite, record.weight >= 0,
                  record.endTime.map({ $0.timeIntervalSince1970.isFinite && $0 >= record.startTime }) ?? true,
                  record.recordedDuration.map({ $0.isFinite && $0 >= 0 && $0 <= 86400 }) ?? true,
                  (record.note?.count ?? 0) <= 2000, record.sets.count <= 10_000,
                  Set(record.sets.map(\.id)).count == record.sets.count,
                  record.sets.allSatisfy({ $0.weight.isFinite && $0.weight >= 0 && (0...1_000_000).contains($0.reps) }),
                  (0...1_000_000).contains(record.reps) else { throw RecordFileError.invalid }
            if let c = record.correction { guard (0...1_000_000).contains(c.reps), c.weight.isFinite, (0...500).contains(c.weight) else { throw RecordFileError.invalid } }
            for summary in [record.legacySummary, record.watchSummary].compactMap({ $0 }) {
                let source = Self.source(summary)
                guard source.valid, summary.id == record.id else { throw RecordFileError.invalid }
            }
        }
        for draft in snapshot.editorDrafts {
            guard draft.date.timeIntervalSince1970.isFinite, draft.sets.count <= 500, draft.note.count <= 2000,
                  Set(draft.sets.map(\.id)).count == draft.sets.count,
                  [draft.duration, draft.summaryReps, draft.summaryWeight].allSatisfy({ $0.count <= 64 }),
                  draft.sets.allSatisfy({ $0.weight.count <= 64 && $0.reps.count <= 64 }) else { throw RecordFileError.invalid }
        }
    }

    private static func source(_ s: WorkoutHistory) -> WorkoutSync.Record {
        WorkoutSync.Record(id: s.id, date: s.date, exercise: s.exerciseType.rawValue, totalReps: s.totalReps,
            maxWeight: s.maxWeight, duration: s.duration, activeDuration: s.activeDuration)
    }
    private static func merge(_ records: [WorkoutSync.Record], into next: inout RecordSnapshot, allowLegacy: Bool = false) throws {
        for record in records {
            guard record.valid, let exercise = ExerciseType(rawValue: record.exercise) else { throw WorkoutSync.Failure.invalidPayload }
            if next.deletedIDs.contains(record.id) { continue }
            let summary = WorkoutHistory(id: record.id, date: record.date, exerciseType: exercise, totalReps: record.totalReps,
                maxWeight: record.maxWeight, duration: record.duration, activeDuration: record.activeDuration)
            if let index = next.history.firstIndex(where: { $0.id == record.id }) {
                if allowLegacy, next.history[index].legacySummary != nil { continue }
                guard let old = next.history[index].watchSummary,
                      source(old).sameSource(as: record), old.activeDuration == nil || record.activeDuration == nil || old.activeDuration == record.activeDuration
                else { throw WorkoutSync.Failure.conflictingRecord }
                if old.activeDuration == nil { next.history[index].watchSummary = summary }
            } else {
                var item = PhoneTrainingSession(id: record.id, startTime: record.date, exercise: exercise, weight: record.maxWeight)
                item.endTime = record.date.addingTimeInterval(record.duration); item.watchSummary = summary
                next.history.append(item)
            }
        }
        next.history.sort { $0.startTime > $1.startTime }
    }

    func acceptWatchHistory(_ records: [WorkoutSync.Record]) throws {
        var next = state
        try Self.merge(records, into: &next)
        guard commit(next) else { throw RecordFileError.unavailable }
    }
    @discardableResult func confirmSync() -> Bool {
        var next = state; next.lastSyncAt = Date(); return commit(next)
    }
    func lastSets(for exercise: ExerciseType) -> [PhoneTrainingSet] {
        history.first { $0.sets.contains { $0.exercise == exercise && !$0.imported } }?.sets.filter { $0.exercise == exercise && !$0.imported } ?? []
    }
    func suggestedWeight(for exercise: ExerciseType) -> Double? {
        if exercise == lastExercise, let lastWeight { return lastWeight }
        guard let latest = history.first(where: { $0.exercises.contains(exercise) }) else { return nil }
        return latest.isSummary ? latest.maxWeight : latest.sets.last(where: { $0.exercise == exercise })?.weight
    }
    @discardableResult func saveDraft(_ draft: RecordEditorDraft) -> Bool {
        var next = state
        next.editorDrafts.removeAll { $0.id == draft.id || ($0.recordID != nil && $0.recordID == draft.recordID) }
        next.editorDrafts.append(draft)
        return commit(next)
    }
    @discardableResult func discardEditorDraft(_ id: UUID) -> Bool {
        var next = state; next.editorDrafts.removeAll { $0.id == id }; return commit(next)
    }
    @discardableResult
    func addRecord(date: Date, sets: [PhoneTrainingSet], duration: TimeInterval?, note: String = "", draftID: UUID? = nil) -> Bool {
        guard validRecord(date: date, sets: sets, duration: duration), note.count <= 2000, let first = sets.first else { return false }
        var record = PhoneTrainingSession(startTime: date, exercise: first.exercise, weight: first.weight)
        record.sets = sets; record.manualEntry = true; record.recordedDuration = duration; record.note = note.isEmpty ? nil : note
        record.endTime = date.addingTimeInterval(duration ?? 0)
        var next = state; next.history.append(record); next.history.sort { $0.startTime > $1.startTime }
        next.lastExercise = sets.last!.exercise; next.lastWeight = sets.last!.weight
        next.editorDrafts.removeAll { $0.id == draftID }
        return commit(next)
    }
    @discardableResult
    func updateRecord(id: UUID, date: Date, sets: [PhoneTrainingSet], duration: TimeInterval?, summaryReps: Int?, summaryWeight: Double?, note: String? = nil, draftID: UUID? = nil) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == id }), (note?.count ?? 0) <= 2000 else { return false }
        var next = state; var record = next.history[index]
        if record.isSummary {
            guard let summaryReps, (0...1_000_000).contains(summaryReps), let summaryWeight, summaryWeight.isFinite, (0...500).contains(summaryWeight) else { return false }
            record.correction = .init(reps: summaryReps, weight: summaryWeight)
        } else {
            guard validRecord(date: date, sets: sets, duration: duration), let first = sets.first else { return false }
            let previousDuration = record.duration
            record.sets = sets; record.exercise = first.exercise; record.weight = first.weight; record.startTime = date
            if record.manualEntry == true { record.recordedDuration = duration; record.endTime = date.addingTimeInterval(duration ?? 0) }
            else { record.endTime = date.addingTimeInterval(previousDuration) }
            next.lastExercise = sets.last!.exercise; next.lastWeight = sets.last!.weight
        }
        if let note { record.note = note.isEmpty ? nil : note }
        next.history[index] = record; next.history.sort { $0.startTime > $1.startTime }
        next.editorDrafts.removeAll { $0.id == draftID || $0.recordID == id }
        return commit(next)
    }
    private func validRecord(date: Date, sets: [PhoneTrainingSet], duration: TimeInterval?) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && date <= Date().addingTimeInterval(60) && !sets.isEmpty && sets.count <= 500 &&
        Set(sets.map(\.id)).count == sets.count && sets.allSatisfy { $0.weight.isFinite && (0...500).contains($0.weight) && (1...999).contains($0.reps) } &&
        (duration.map { $0.isFinite && $0 >= 0 && $0 <= 86400 } ?? true)
    }
    @discardableResult func deleteRecords(ids: Set<UUID>) -> Bool {
        var next = state
        let actual = ids.intersection(history.map(\.id))
        next.deletedIDs.formUnion(actual); next.history.removeAll { actual.contains($0.id) }
        next.editorDrafts.removeAll { $0.recordID.map(actual.contains) ?? false }
        return commit(next)
    }
    func deleteHistory(at offsets: IndexSet) { _ = deleteRecords(ids: Set(offsets.compactMap { history.indices.contains($0) ? history[$0].id : nil })) }
    func deleteRecord(id: UUID) { _ = deleteRecords(ids: [id]) }
    func finish() {
        guard var item = state.session else { return }
        if item.reps > 0 { item.sets.append(PhoneTrainingSet(exercise: item.exercise, weight: item.weight, reps: item.reps)) }
        guard !item.sets.isEmpty else { return }
        item.reps = 0; item.restEndsAt = nil; item.endTime = Date()
        var next = state; next.session = nil; next.history.insert(item, at: 0)
        if commit(next) { cancelLegacyReminder() }
    }
    func cancelEmptyTraining() {
        guard let item = state.session, item.sets.isEmpty, item.reps == 0 else { return }
        var next = state; next.session = nil
        if commit(next) { cancelLegacyReminder() }
    }
    private func cancelLegacyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID])
    }

    func backupData() throws -> Data {
        guard readable else { throw RecordFileError.unavailable }
        return try JSONEncoder().encode(RecordBackup(snapshot: state))
    }
    func previewRestore(_ data: Data) throws -> RecordRestorePreview {
        guard readable else { throw RecordFileError.unavailable }
        guard data.count <= 32 * 1024 * 1024 else { throw RecordFileError.invalid }
        let backup: RecordBackup
        do { backup = try JSONDecoder().decode(RecordBackup.self, from: data) }
        catch { throw RecordFileError.invalid }
        guard backup.format == "com.flyingrtx.powerreps.records", backup.version == 1 else { throw RecordFileError.unsupported }
        try Self.validate(backup.snapshot)
        let present = Set(history.map(\.id)).union(state.deletedIDs)
        let added = backup.snapshot.history.filter { !present.contains($0.id) }.count
        let drafts = mergedDrafts(backup.snapshot.editorDrafts).count - state.editorDrafts.count
        return RecordRestorePreview(backup: backup, added: added, skipped: backup.snapshot.history.count - added, drafts: drafts)
    }
    private func mergedDrafts(_ incoming: [RecordEditorDraft]) -> [RecordEditorDraft] {
        var result = state.editorDrafts
        for draft in incoming {
            if let id = draft.recordID, state.deletedIDs.contains(id) { continue }
            if !result.contains(where: { $0.id == draft.id || ($0.recordID != nil && $0.recordID == draft.recordID) }) { result.append(draft) }
        }
        return result
    }
    func restore(_ preview: RecordRestorePreview) throws {
        // Recompute from current state: Watch batches may have arrived during preview.
        try Self.validate(preview.backup.snapshot)
        var next = state
        let existing = Set(history.map(\.id)), blocked = existing.union(state.deletedIDs)
        next.history += preview.backup.snapshot.history.filter { !blocked.contains($0.id) }
        next.deletedIDs.formUnion(preview.backup.snapshot.deletedIDs.subtracting(existing))
        next.editorDrafts = mergedDrafts(preview.backup.snapshot.editorDrafts)
        if next.session == nil { next.session = preview.backup.snapshot.session }
        next.history.sort { $0.startTime > $1.startTime }
        try Self.validate(next)
        try Self.write(state, to: snapshotURL.deletingLastPathComponent().appendingPathComponent("before-restore.json"))
        guard commit(next) else { throw RecordFileError.unavailable }
    }

    func csv(records: [PhoneTrainingSession], sets: Bool, exercise: ExerciseType? = nil) -> String {
        func escaped(_ value: String) -> String {
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: value.hasPrefix) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let number: (Double) -> String = { String($0) }
        var rows = [sets ? ["record_id", "date", "exercise", "set", "reps", "weight_kg", "note"] : ["record_id", "date", "exercise", "reps", "max_weight_kg", "duration_seconds", "note"]]
        for item in records {
            let prefix = [item.id.uuidString, item.startTime.ISO8601Format()]
            if sets {
                for (index, set) in item.sets.enumerated() where exercise == nil || set.exercise == exercise {
                    rows.append(prefix + [set.exercise.rawValue, String(index + 1), String(set.reps), number(set.weight), item.note ?? ""])
                }
            } else {
                let selected = item.sets.filter { exercise == nil || $0.exercise == exercise }
                let reps = item.isSummary || exercise == nil ? item.totalReps : selected.reduce(0) { $0 + $1.reps }
                let weight = item.isSummary || exercise == nil ? item.maxWeight : selected.map(\.weight).max() ?? 0
                rows.append(prefix + [(exercise.map { [$0] } ?? item.exercises).map(\.rawValue).joined(separator: ";"), String(reps), number(weight), item.displayDuration.map(number) ?? "", item.note ?? ""])
            }
        }
        return "\u{FEFF}" + rows.map { $0.map(escaped).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
