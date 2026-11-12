import Foundation
import Combine
import UserNotifications

struct PhoneTrainingSet: Codable, Identifiable, Equatable {
    var id = UUID()
    let exercise: ExerciseType
    let weight: Double
    let reps: Int
    var imported = false
}

struct PhoneTrainingSession: Codable, Identifiable, Equatable {
    struct Correction: Codable, Equatable {
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
    var reportGrouping: [[UUID]]?
    private var summary: WorkoutHistory? { watchSummary ?? legacySummary }

    var sourceWorkoutReport: WorkoutReport? { summary?.workoutReport }
    var workoutReport: WorkoutReport? { try? groupedWorkoutReport() }
    func groupedWorkoutReport() throws -> WorkoutReport? {
        guard var report = sourceWorkoutReport else {
            guard reportGrouping == nil else { throw RecordFileError.invalid }
            return nil
        }
        guard let grouping = reportGrouping else { return report }
        let original = report.sets.flatMap(\.repetitions)
        guard grouping.count <= 1_000, grouping.allSatisfy({ !$0.isEmpty }),
              grouping.flatMap({ $0 }) == original.map(\.id) else { throw RecordFileError.invalid }
        let reps = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) })
        let exercises = Dictionary(uniqueKeysWithValues: report.sets.flatMap { set in set.repetitions.map { ($0.id, set.exercise) } })
        report.sets = try grouping.map { ids in
            guard let first = ids.first, let exercise = exercises[first], ids.allSatisfy({ exercises[$0] == exercise }) else { throw RecordFileError.invalid }
            return WorkoutReport.SetRecord(id: first, exercise: exercise, repetitions: ids.compactMap { reps[$0] })
        }
        try report.validate()
        return report
    }
    var hasKnownWeight: Bool { correction != nil || (workoutReport?.hasKnownWeights ?? true) }
    var reportMatchesCorrection: Bool {
        guard let correction, let summary else { return true }
        return correction.reps == summary.totalReps && correction.weight == summary.maxWeight
    }
    // Only source-aligned sets can contribute to filters and statistics.
    var measuredSets: [PhoneTrainingSet] {
        if let report = workoutReport, reportMatchesCorrection, report.hasKnownWeights {
            return report.sets.compactMap { set in
                guard let weight = set.repetitions.first?.weight,
                      set.repetitions.allSatisfy({ $0.weight == weight }) else { return nil }
                return PhoneTrainingSet(id: set.id, exercise: set.exercise, weight: weight, reps: set.totalReps)
            }
        }
        return isSummary ? [] : sets
    }
    func repetitions(for exercise: ExerciseType?) -> Int {
        guard let exercise else { return totalReps }
        if let report = workoutReport {
            guard reportMatchesCorrection else { return 0 }
            return report.sets.filter { $0.exercise == exercise }.reduce(0) { $0 + $1.totalReps }
        }
        return isSummary ? totalReps : sets.filter { $0.exercise == exercise }.reduce(0) { $0 + $1.reps }
    }
    func maximumWeight(for exercise: ExerciseType?) -> Double {
        guard let exercise else { return maxWeight }
        if let report = workoutReport {
            guard reportMatchesCorrection else { return 0 }
            return report.sets.filter { $0.exercise == exercise }.map(\.maxWeight).max() ?? 0
        }
        return isSummary ? maxWeight : sets.filter { $0.exercise == exercise }.map(\.weight).max() ?? 0
    }
    func measuredActiveDuration(for exercise: ExerciseType?) -> TimeInterval? {
        guard let exercise, let report = workoutReport else { return activeDuration }
        guard reportMatchesCorrection else { return nil }
        let sets = report.sets.filter { $0.exercise == exercise }
        let measured = sets.compactMap(\.activeDuration)
        guard !sets.isEmpty, measured.count == sets.count else { return nil }
        return measured.reduce(0, +)
    }
    var totalReps: Int { correction?.reps ?? summary?.totalReps ?? sets.reduce(0) { $0 + $1.reps } }
    var maxWeight: Double { correction?.weight ?? summary?.maxWeight ?? sets.map(\.weight).max() ?? weight }
    var isSummary: Bool { summary != nil }
    var displayDuration: TimeInterval? { activeDuration }
    var duration: TimeInterval { summary?.duration ?? max(0, (endTime ?? Date()).timeIntervalSince(startTime)) }
    var activeDuration: TimeInterval? {
        if manualEntry == true { return recordedDuration }
        guard let summary, correction.map({ $0.reps == summary.totalReps }) ?? true else { return nil }
        return summary.activeDuration ?? sourceWorkoutReport?.activeDuration
    }
    var exercises: [ExerciseType] {
        if let report = workoutReport { return ExerciseType.allCases.filter { exercise in report.sets.contains { $0.exercise == exercise } } }
        if let summary { return [summary.exerciseType] }
        return ExerciseType.allCases.filter { exercise in sets.contains { $0.exercise == exercise } }
    }
    var volume: Double? {
        if let report = workoutReport, !report.hasKnownWeights { return nil }
        if let summary {
            guard totalReps == summary.totalReps, maxWeight == summary.maxWeight else { return nil }
            return summary.totalWeight
        }
        return sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
}

struct RecordFilter: Equatable, Codable {
    enum Period: String, CaseIterable, Codable { case week, month, quarter, all, custom
        var title: String { switch self {
            case .week: String(localized: "近7天")
            case .month: String(localized: "近30天")
            case .quarter: String(localized: "近90天")
            case .all: String(localized: "全部时间")
            case .custom: String(localized: "自定义日期")
        } }
    }
    var exercise: ExerciseType?
    var period = Period.all
    var start = Calendar.current.startOfDay(for: Date())
    var end = Date()
    mutating func select(_ interval: DateInterval) {
        start = interval.start; end = min(interval.end.addingTimeInterval(-1), Date()); period = .custom
    }
    func intersection(with interval: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        guard period != .all else { return interval }
        let lower: Date
        let upper: Date
        if period == .custom {
            lower = calendar.startOfDay(for: start)
            upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        } else {
            let days = period == .week ? 6 : period == .month ? 29 : 89
            lower = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
            upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        }
        let a = max(lower, interval.start), b = min(upper, interval.end)
        return b > a ? DateInterval(start: a, end: b) : nil
    }
    func includes(_ item: PhoneTrainingSession) -> Bool {
        (exercise == nil || (item.exercises.contains(exercise!) && (item.workoutReport == nil || item.reportMatchesCorrection))) && includes(item.startTime)
    }
    func includes(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch period {
        case .all: return true
        case .custom:
            return date >= calendar.startOfDay(for: start) && date < calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        default:
            let days = period == .week ? 6 : period == .month ? 29 : 89
            return date >= calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date()))! && date <= Date()
        }
    }
    var rangeTitle: String {
        period == .custom ? start.formatted(date: .abbreviated, time: .omitted) + " – " + end.formatted(date: .abbreviated, time: .omitted) : period.title
    }
    func reps(_ item: PhoneTrainingSession) -> Int {
        item.repetitions(for: exercise)
    }
    func weight(_ item: PhoneTrainingSession) -> Double {
        item.maximumWeight(for: exercise)
    }
}

enum RecordTimeMetric: String, CaseIterable, Hashable {
    case active

    var title: String { String(localized: "训练时长") }

    func seconds(in record: PhoneTrainingSession, exercise: ExerciseType? = nil) -> TimeInterval? {
        let value = record.measuredActiveDuration(for: exercise)
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

enum RecordChartGranularity: String, CaseIterable, Codable, Hashable {
    case automatic, day, week, month

    var title: String {
        switch self {
        case .automatic: String(localized: "自动汇总")
        case .day: String(localized: "按日")
        case .week: String(localized: "按周")
        case .month: String(localized: "按月")
        }
    }

    var recordsTitle: String {
        switch self {
        case .automatic, .day: String(localized: "每日记录")
        case .week: String(localized: "每周记录")
        case .month: String(localized: "每月记录")
        }
    }

    func resolved(for dates: [Date], calendar: Calendar = .current) -> Self {
        guard self == .automatic else { return self }
        guard let first = dates.min(), let last = dates.max() else { return .day }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last)).day ?? 0
        return days <= 45 ? .day : days <= 180 ? .week : .month
    }

    var component: Calendar.Component {
        switch self {
        case .automatic, .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86400)
    }
}

struct RecordDurationDay: Identifiable, Equatable {
    let id: Date
    let range: DateInterval
    let seconds: TimeInterval
    let measuredRecords: Int
    let recordCount: Int

    static func summarize(_ records: [PhoneTrainingSession], metric: RecordTimeMetric, granularity: RecordChartGranularity = .day, calendar: Calendar = .current, exercise: ExerciseType? = nil) -> [Self] {
        let grouping = granularity.resolved(for: records.map(\.startTime), calendar: calendar)
        return Dictionary(grouping: records, by: { grouping.interval(containing: $0.startTime, calendar: calendar).start }).compactMap { start, records in
            let values = records.compactMap { metric.seconds(in: $0, exercise: exercise) }
            guard !values.isEmpty else { return nil }
            return Self(id: start, range: grouping.interval(containing: start, calendar: calendar), seconds: values.reduce(0, +), measuredRecords: values.count, recordCount: records.count)
        }.sorted { $0.id < $1.id }
    }
}

struct RecordTrendBucket: Identifiable, Equatable {
    let id: Date
    let range: DateInterval
    let sessions: Int
    let reps: Int
    let weight: Double

    static func summarize(_ records: [PhoneTrainingSession], granularity: RecordChartGranularity,
                          calendar: Calendar = .current, reps: (PhoneTrainingSession) -> Int,
                          weight: (PhoneTrainingSession) -> Double) -> [Self] {
        let grouping = granularity.resolved(for: records.map(\.startTime), calendar: calendar)
        return Dictionary(grouping: records, by: { grouping.interval(containing: $0.startTime, calendar: calendar).start }).map { start, rows in
            Self(id: start, range: grouping.interval(containing: start, calendar: calendar), sessions: rows.count,
                 reps: rows.reduce(0) { $0 + reps($1) }, weight: rows.map(weight).max() ?? 0)
        }.sorted { $0.id < $1.id }
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
    var version = 4
    var session: PhoneTrainingSession?
    var history: [PhoneTrainingSession] = []
    var deletedIDs: Set<UUID> = []
    var editorDrafts: [RecordEditorDraft] = []
    var lastExercise: ExerciseType = .benchPress
    var lastWeight: Double?
    var lastSyncAt: Date?
}

struct RecordReportSensorBackup: Codable {
    let workoutID: UUID
    let timeline: WorkoutTimeline
}

struct RecordBackup: Codable {
    var format = "com.flyingrtx.powerreps.records"
    var version = 4
    var createdAt = Date()
    var snapshot: RecordSnapshot
    var timelines: [WorkoutTimeline]? = nil
    var reportSensors: [RecordReportSensorBackup]? = nil
}

struct RecordRestorePreview: Identifiable {
    let id = UUID()
    let backup: RecordBackup
    let added: Int
    let skipped: Int
    let drafts: Int
}

enum RecordFileError: LocalizedError {
    case invalid, unsupported, unavailable, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalid: return String(localized: "备份文件损坏或内容无效")
        case .unsupported: return String(localized: "不支持此备份版本")
        case .unavailable: return String(localized: "记录未能保存，请重试")
        case .tooLarge: return String(localized: "训练记录备份不能超过 256 MB")
        }
    }
}

@MainActor
final class PhoneWorkoutStore: ObservableObject {
    @Published private var state = RecordSnapshot()
    @Published private(set) var storageError: String?
    @Published private(set) var timelineRevision = 0
    @Published private(set) var historyRevision = 0
    @Published private(set) var storageBusy = false
    private var storageWaiters: [CheckedContinuation<Void, Never>] = []
    private var readable = true
    let snapshotURL: URL
    nonisolated static let maximumBackupBytes = 256 * 1024 * 1024
    nonisolated private static let maximumTimelineBytes = WorkoutTimeline.maximumFileBytes
    private var timelineFolder: URL { snapshotURL.deletingLastPathComponent().appendingPathComponent("Timelines", isDirectory: true) }
    private let defaults: UserDefaults
    private let reminderID: String
    var history: [PhoneTrainingSession] { state.history }
    var trainingDates: [Date] { state.history.filter { $0.totalReps > 0 }.map(\.startTime) }
    var onTrainingDatesChanged: (([Date]) -> Void)?
    var session: PhoneTrainingSession? { state.session }
    var editorDrafts: [RecordEditorDraft] { state.editorDrafts }
    var lastExercise: ExerciseType { state.lastExercise }
    var lastWeight: Double? { state.lastWeight }
    var lastSyncAt: Date? { state.lastSyncAt }
    var requiresRecovery: Bool { !readable }

    private func beginFileOperation() async {
        if storageBusy { await withCheckedContinuation { storageWaiters.append($0) } }
        else { storageBusy = true }
    }
    private func endFileOperation() {
        if storageWaiters.isEmpty { storageBusy = false }
        else { storageWaiters.removeFirst().resume() }
    }
    private func publish(_ snapshot: RecordSnapshot) {
        var next = snapshot
        next.version = 4
        let historyChanged = state.history != next.history
        let oldDates = historyChanged ? trainingDates : []
        if historyChanged { historyRevision &+= 1 }
        state = next
        storageError = nil
        if historyChanged, trainingDates != oldDates { onTrainingDatesChanged?(trainingDates) }
    }

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
                let original = try Data(contentsOf: self.snapshotURL)
                var decoded = try JSONDecoder().decode(RecordSnapshot.self, from: original)
                try Self.validate(decoded)
                if decoded.version == 3 {
                    let before = self.snapshotURL.deletingLastPathComponent().appendingPathComponent("before-schema4.json")
                    if !FileManager.default.fileExists(atPath: before.path) {
                        try original.write(to: before, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                    decoded.version = 4
                    try Self.write(decoded, to: self.snapshotURL)
                }
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
                try Self.merge(archive.records, into: &next)
                try Self.validate(next)
                try Self.write(next, to: self.snapshotURL)
                state = next
            }
        } catch {
            readable = false
            storageError = String(localized: "本地记录无法读取，请从备份恢复")
        }
    }


    nonisolated fileprivate static func write(_ snapshot: RecordSnapshot, to url: URL) throws {
        var snapshot = snapshot
        snapshot.version = 4
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    @discardableResult
    private func commit(_ next: RecordSnapshot) -> Bool {
        guard readable, !storageBusy else {
            storageError = String(localized: "记录未能保存，请重试")
            return false
        }
        do {
            try Self.validate(next)
            try Self.write(next, to: snapshotURL)
            publish(next)
            return true
        } catch {
            storageError = String(localized: "记录未能保存，请重试")
            return false
        }
    }

    nonisolated static func validate(_ snapshot: RecordSnapshot) throws {
        guard (3...4).contains(snapshot.version) else { throw RecordFileError.unsupported }
        guard snapshot.history.count <= 100_000, Set(snapshot.history.map(\.id)).count == snapshot.history.count,
              snapshot.deletedIDs.isDisjoint(with: snapshot.history.map(\.id)),
              snapshot.editorDrafts.count <= 500, Set(snapshot.editorDrafts.map(\.id)).count == snapshot.editorDrafts.count,
              snapshot.lastWeight.map({ $0.isFinite && $0 >= 0 }) ?? true,
              snapshot.lastSyncAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw RecordFileError.invalid }
        for record in snapshot.history + (snapshot.session.map { [$0] } ?? []) {
            if snapshot.version == 3, record.reportGrouping != nil || record.sourceWorkoutReport != nil { throw RecordFileError.invalid }
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
            _ = try record.groupedWorkoutReport()
        }
        for draft in snapshot.editorDrafts {
            guard draft.date.timeIntervalSince1970.isFinite, draft.sets.count <= 500, draft.note.count <= 2000,
                  Set(draft.sets.map(\.id)).count == draft.sets.count,
                  [draft.duration, draft.summaryReps, draft.summaryWeight].allSatisfy({ $0.count <= 64 }),
                  draft.sets.allSatisfy({ $0.weight.count <= 64 && $0.reps.count <= 64 }) else { throw RecordFileError.invalid }
        }
    }

    nonisolated fileprivate static func source(_ s: WorkoutHistory) -> WorkoutSync.Record {
        WorkoutSync.Record(id: s.id, date: s.date, exercise: s.exerciseType.rawValue, totalReps: s.totalReps,
            maxWeight: s.maxWeight, duration: s.duration, activeDuration: s.activeDuration, totalWeight: s.totalWeight, workoutReport: s.workoutReport)
    }
    nonisolated fileprivate static func compatible(_ a: WorkoutSync.Record, _ b: WorkoutSync.Record) -> Bool {
        a.sameSource(as: b) &&
        (a.activeDuration == nil || b.activeDuration == nil || a.activeDuration == b.activeDuration) &&
        (a.totalWeight == nil || b.totalWeight == nil || a.totalWeight == b.totalWeight) &&
        (a.workoutReport == nil || b.workoutReport == nil || a.workoutReport == b.workoutReport)
    }
    nonisolated fileprivate static func validate(_ timeline: WorkoutTimeline, for record: PhoneTrainingSession) throws {
        guard let summary = record.watchSummary ?? record.legacySummary,
              compatible(source(summary), timeline.source) else { throw WorkoutSync.Failure.conflictingRecord }
    }
    nonisolated fileprivate static func reportSource(_ record: PhoneTrainingSession) throws -> WorkoutSync.Record {
        guard let summary = record.watchSummary ?? record.legacySummary,
              summary.workoutReport != nil else { throw WorkoutSync.Failure.conflictingRecord }
        return source(summary)
    }
    private var timelineArchive: WorkoutTimelineArchive { WorkoutTimelineArchive(folder: timelineFolder) }
    private var reportSensorArchive: WorkoutReportSensorArchive {
        WorkoutReportSensorArchive(folder: snapshotURL.deletingLastPathComponent().appendingPathComponent("ReportSensors", isDirectory: true))
    }

    func timeline(for id: UUID) throws -> WorkoutTimeline? {
        guard !state.deletedIDs.contains(id), let record = history.first(where: { $0.id == id }),
              let timeline = try timelineArchive.load(id) else { return nil }
        try Self.validate(timeline, for: record)
        return timeline
    }

    // A file may arrive before its summary. Keep it durably without creating a
    // visible training record; the later summary must match its original source.
    @discardableResult
    func acceptWatchTimeline(_ timeline: WorkoutTimeline) throws -> Bool {
        guard readable else { throw RecordFileError.unavailable }
        try timeline.validate()
        if state.deletedIDs.contains(timeline.id) { return false }
        if let record = history.first(where: { $0.id == timeline.id }) { try Self.validate(timeline, for: record) }
        guard try JSONEncoder().encode(timeline).count <= Self.maximumTimelineBytes else { throw RecordFileError.invalid }
        try timelineArchive.retain(timeline)
        var next = state
        if try Self.enrichDuration(from: timeline, into: &next), !commit(next) { throw RecordFileError.unavailable }
        timelineRevision &+= 1
        return true
    }
    nonisolated fileprivate static func merge(_ records: [WorkoutSync.Record], into next: inout RecordSnapshot) throws {
        for record in records {
            guard record.valid, let exercise = ExerciseType(rawValue: record.exercise) else { throw WorkoutSync.Failure.invalidPayload }
            if next.deletedIDs.contains(record.id) { continue }
            let summary = WorkoutHistory(id: record.id, date: record.date, exerciseType: exercise, totalReps: record.totalReps,
                maxWeight: record.maxWeight, duration: record.duration, activeDuration: record.activeDuration, totalWeight: record.totalWeight, workoutReport: record.workoutReport)
            if let index = next.history.firstIndex(where: { $0.id == record.id }) {
                guard let old = next.history[index].watchSummary ?? next.history[index].legacySummary,
                      source(old).sameSource(as: record),
                      old.activeDuration == nil || record.activeDuration == nil || old.activeDuration == record.activeDuration,
                      old.totalWeight == nil || record.totalWeight == nil || old.totalWeight == record.totalWeight,
                      old.workoutReport == nil || record.workoutReport == nil || old.workoutReport == record.workoutReport
                else { throw WorkoutSync.Failure.conflictingRecord }
                var merged = old
                if old.activeDuration == nil { merged.activeDuration = summary.activeDuration }
                if old.totalWeight == nil { merged.totalWeight = summary.totalWeight }
                if old.workoutReport == nil { merged.workoutReport = summary.workoutReport }
                next.history[index].watchSummary = merged
            } else {
                var item = PhoneTrainingSession(id: record.id, startTime: record.date, exercise: exercise, weight: record.maxWeight)
                item.endTime = record.date.addingTimeInterval(record.duration); item.watchSummary = summary
                next.history.append(item)
            }
        }
        next.history.sort { $0.startTime > $1.startTime }
    }

    func acceptWatchHistory(_ records: [WorkoutSync.Record]) throws {
        guard readable, !storageBusy else { throw RecordFileError.unavailable }
        let next = try RecordFileWorkspace(snapshot: state, snapshotURL: snapshotURL).acceptHistory(records)
        guard commit(next) else { throw RecordFileError.unavailable }
    }
    nonisolated fileprivate static func enrichDuration(from timeline: WorkoutTimeline, into snapshot: inout RecordSnapshot) throws -> Bool {
        guard let record = snapshot.history.first(where: { $0.id == timeline.id }),
              let summary = record.watchSummary ?? record.legacySummary, summary.activeDuration == nil else { return false }
        try Self.validate(timeline, for: record)
        guard let measured = timeline.estimatedActiveDuration else { return false }
        var enriched = timeline.source
        enriched.activeDuration = measured
        try Self.merge([enriched], into: &snapshot)
        return true
    }
    @discardableResult func confirmSync() -> Bool {
        var next = state; next.lastSyncAt = Date(); return commit(next)
    }
    func lastSets(for exercise: ExerciseType) -> [PhoneTrainingSet] {
        history.first { $0.sets.contains { $0.exercise == exercise && !$0.imported } }?.sets.filter { $0.exercise == exercise && !$0.imported } ?? []
    }
    func suggestedWeight(for exercise: ExerciseType) -> Double? {
        if exercise == lastExercise, let lastWeight { return lastWeight }
        guard let latest = history.first(where: { $0.exercises.contains(exercise) && $0.hasKnownWeight }) else { return nil }
        return latest.isSummary ? latest.maxWeight : latest.sets.last(where: { $0.exercise == exercise })?.weight
    }
    @discardableResult func saveDraft(_ draft: RecordEditorDraft) -> Bool {
        var next = state
        next.editorDrafts.removeAll { $0.id == draft.id || ($0.recordID != nil && $0.recordID == draft.recordID) }
        next.editorDrafts.append(draft)
        return commit(next)
    }
    @discardableResult func discardEditorDraft(_ id: UUID) -> Bool {
        guard state.editorDrafts.contains(where: { $0.id == id }) else { return true }
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
    @discardableResult
    func updateReportGrouping(id: UUID, groups: [[UUID]]?) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == id }), history[index].sourceWorkoutReport != nil else { return false }
        var next = state
        next.history[index].reportGrouping = groups
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
        guard commit(next) else { return false }
        // Durable tombstones take effect before sidecar cleanup. A delayed file
        // is acknowledged and discarded even if cleanup is interrupted.
        for id in actual {
            try? timelineArchive.remove(id)
            try? reportSensorArchive.remove(id)
        }
        if !actual.isEmpty { timelineRevision &+= 1 }
        return true
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
        return try RecordFileWorkspace(snapshot: state, snapshotURL: snapshotURL).backupData()
    }
    @discardableResult
    nonisolated fileprivate static func validateBackup(_ backup: RecordBackup) throws -> Int {
        guard backup.format == "com.flyingrtx.powerreps.records", (1...4).contains(backup.version) else { throw RecordFileError.unsupported }
        guard backup.version >= 3 || backup.snapshot.version <= 3 else { throw RecordFileError.invalid }
        try validate(backup.snapshot)
        let timelines = backup.timelines ?? []
        guard (backup.version >= 2 || timelines.isEmpty), timelines.count <= backup.snapshot.history.count,
              Set(timelines.map(\.id)).count == timelines.count else { throw RecordFileError.invalid }
        let records = Dictionary(uniqueKeysWithValues: backup.snapshot.history.map { ($0.id, $0) })
        let reportSensors = backup.reportSensors ?? []
        guard backup.version >= 4 || reportSensors.isEmpty else { throw RecordFileError.invalid }
        var sensorIDs = Set<UUID>()
        var sensorCounts: [UUID: Int] = [:]
        var header = backup; header.timelines = nil; header.reportSensors = nil
        var bytes = try JSONEncoder().encode(header).count
        if backup.timelines != nil { bytes += ",\"timelines\":[]".utf8.count + max(0, timelines.count - 1) }
        for timeline in timelines {
            try timeline.validate()
            let size = try JSONEncoder().encode(timeline).count
            guard let record = records[timeline.id], size <= maximumTimelineBytes else { throw RecordFileError.invalid }
            bytes += size
            guard bytes <= maximumBackupBytes else { throw RecordFileError.tooLarge }
            try validate(timeline, for: record)
        }
        if backup.reportSensors != nil { bytes += ",\"reportSensors\":[]".utf8.count + max(0, reportSensors.count - 1) }
        for sensor in reportSensors {
            guard sensorIDs.insert(sensor.timeline.id).inserted,
                  let record = records[sensor.workoutID] else { throw RecordFileError.invalid }
            sensorCounts[sensor.workoutID, default: 0] += 1
            guard sensorCounts[sensor.workoutID, default: 0] <= WorkoutReportSensors.maximumSegments else { throw RecordFileError.invalid }
            let source = try reportSource(record)
            try WorkoutReportSensorArchive.validate(sensor.timeline, for: source)
            guard try JSONEncoder().encode(sensor.timeline).count <= maximumTimelineBytes else { throw RecordFileError.invalid }
            bytes += try JSONEncoder().encode(sensor).count
            guard bytes <= maximumBackupBytes else { throw RecordFileError.tooLarge }
        }
        guard bytes <= maximumBackupBytes else { throw RecordFileError.tooLarge }
        return bytes
    }
    func previewRestore(_ data: Data) throws -> RecordRestorePreview {
        guard data.count <= Self.maximumBackupBytes else { throw RecordFileError.tooLarge }
        let backup: RecordBackup
        do { backup = try JSONDecoder().decode(RecordBackup.self, from: data) }
        catch { throw RecordFileError.invalid }
        try Self.validateBackup(backup)
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
        guard !storageBusy else { throw RecordFileError.unavailable }
        let next = try RecordFileWorkspace(snapshot: state, snapshotURL: snapshotURL).restore(preview, readable: readable)
        readable = true; publish(next); timelineRevision &+= 1
    }

    func confirmReceivedSync() async -> Bool {
        await beginFileOperation(); defer { endFileOperation() }
        guard readable else { return false }
        var next = state; next.lastSyncAt = Date()
        let url = snapshotURL
        do {
            try await WorkoutFileIO.shared.perform { try Self.validate(next); try Self.write(next, to: url) }
            publish(next); return true
        } catch { storageError = String(localized: "记录未能保存，请重试"); return false }
    }

    func exportBeforeRestore() async throws -> URL {
        let directory = snapshotURL.deletingLastPathComponent()
        return try await WorkoutFileIO.shared.perform {
            let full = directory.appendingPathComponent("before-restore-training-records.json")
            let result = FileManager.default.temporaryDirectory.appendingPathComponent("PowerReps-BeforeRestore-" + UUID().uuidString + ".json")
            if FileManager.default.fileExists(atPath: full.path) {
                _ = try Self.decodeBackup(at: full)
                try FileManager.default.copyItem(at: full, to: result)
            } else {
                let state = try JSONDecoder().decode(RecordSnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("before-restore.json")))
                try Self.validate(state)
                try JSONEncoder().encode(RecordBackup(snapshot: state)).write(to: result, options: .atomic)
            }
            return result
        }
    }

    func loadTimeline(_ id: UUID) async throws -> WorkoutTimeline? {
        let archive = timelineArchive
        let result = try await WorkoutFileIO.shared.perform { try archive.load(id) }
        guard !state.deletedIDs.contains(id), let record = history.first(where: { $0.id == id }), let result else { return nil }
        try Self.validate(result, for: record)
        return result
    }

    func loadReportSensorIndex(_ id: UUID) async throws -> [WorkoutReportSensorSummary] {
        await beginFileOperation(); defer { endFileOperation() }
        guard readable else { throw RecordFileError.unavailable }
        guard !state.deletedIDs.contains(id), let record = history.first(where: { $0.id == id }) else { return [] }
        let source = try Self.reportSource(record), archive = reportSensorArchive
        return try await WorkoutFileIO.shared.perform { try archive.index(for: source) }
    }

    func loadReportSensor(_ id: UUID, segmentID: UUID) async throws -> WorkoutTimeline? {
        await beginFileOperation(); defer { endFileOperation() }
        guard readable else { throw RecordFileError.unavailable }
        guard !state.deletedIDs.contains(id), let record = history.first(where: { $0.id == id }) else { return nil }
        let source = try Self.reportSource(record), archive = reportSensorArchive
        return try await WorkoutFileIO.shared.perform {
            guard let timeline = try archive.load(workoutID: id, segmentID: segmentID) else { return nil }
            try WorkoutReportSensorArchive.validate(timeline, for: source)
            return timeline
        }
    }

    func receiveWatchReportSensorFile(_ url: URL, workoutID: UUID, segmentID: UUID) async throws {
        await beginFileOperation(); defer { endFileOperation() }
        guard readable else { throw RecordFileError.unavailable }
        // A durable deletion wins over late files. Otherwise keep the transport
        // inbox retryable until its immutable parent report has arrived.
        if state.deletedIDs.contains(workoutID) { return }
        guard let record = history.first(where: { $0.id == workoutID }) else { throw RecordFileError.unavailable }
        let source = try Self.reportSource(record), archive = reportSensorArchive
        try await WorkoutFileIO.shared.perform {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= Self.maximumTimelineBytes else { throw RecordFileError.invalid }
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maximumTimelineBytes else { throw RecordFileError.invalid }
            let timeline = try JSONDecoder().decode(WorkoutTimeline.self, from: data)
            guard timeline.id == segmentID else { throw WorkoutSync.Failure.invalidPayload }
            try archive.retain(timeline, for: source)
        }
        timelineRevision &+= 1
    }

    func receiveWatchHistory(_ records: [WorkoutSync.Record]) async throws {
        await beginFileOperation(); defer { endFileOperation() }
        guard readable else { throw RecordFileError.unavailable }
        let files = RecordFileWorkspace(snapshot: state, snapshotURL: snapshotURL)
        let next = try await WorkoutFileIO.shared.perform {
            let next = try files.acceptHistory(records)
            try Self.validate(next); try Self.write(next, to: files.snapshotURL)
            return next
        }
        publish(next)
    }

    func receiveWatchTimeline(_ data: Data, id: UUID) async throws {
        try await receiveTimeline(loading: { data }, id: id)
    }
    func receiveWatchTimelineFile(_ url: URL, id: UUID) async throws {
        try await receiveTimeline(loading: { try Data(contentsOf: url) }, id: id)
    }
    private func receiveTimeline(loading: @escaping () throws -> Data, id: UUID) async throws {
        await beginFileOperation(); defer { endFileOperation() }
        guard readable else { throw RecordFileError.unavailable }
        let files = RecordFileWorkspace(snapshot: state, snapshotURL: snapshotURL)
        let next = try await WorkoutFileIO.shared.perform { try files.acceptTimeline(try loading(), id: id) }
        publish(next); timelineRevision &+= 1
    }

    func exportBackup() async throws -> URL {
        await beginFileOperation(); defer { endFileOperation() }
        guard readable else { throw RecordFileError.unavailable }
        let files = RecordFileWorkspace(snapshot: state, snapshotURL: snapshotURL)
        return try await WorkoutFileIO.shared.perform {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("PowerReps-Backup-" + UUID().uuidString + ".json")
            do { try files.writeBackup(to: url); return url }
            catch { try? FileManager.default.removeItem(at: url); throw error }
        }
    }

    func readBackup(_ url: URL) async throws -> RecordRestorePreview {
        let backup = try await WorkoutFileIO.shared.perform { try Self.decodeBackup(at: url) }
        return preview(backup)
    }
    nonisolated private static func decodeBackup(at url: URL) throws -> RecordBackup {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= maximumBackupBytes else { throw RecordFileError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBackupBytes else { throw RecordFileError.tooLarge }
        let backup: RecordBackup
        do { backup = try JSONDecoder().decode(RecordBackup.self, from: data) }
        catch { throw RecordFileError.invalid }
        try validateBackup(backup)
        return backup
    }
    private func preview(_ backup: RecordBackup) -> RecordRestorePreview {
        let present = Set(history.map(\.id)).union(state.deletedIDs)
        let added = backup.snapshot.history.filter { !present.contains($0.id) }.count
        let drafts = mergedDrafts(backup.snapshot.editorDrafts).count - state.editorDrafts.count
        return RecordRestorePreview(backup: backup, added: added, skipped: backup.snapshot.history.count - added, drafts: drafts)
    }

    func mergeBackup(_ preview: RecordRestorePreview) async throws {
        await beginFileOperation(); defer { endFileOperation() }
        let files = RecordFileWorkspace(snapshot: state, snapshotURL: snapshotURL), canRead = readable
        let next = try await WorkoutFileIO.shared.perform { try files.restore(preview, readable: canRead) }
        readable = true; publish(next); timelineRevision &+= 1
    }

    func enrichRetainedDurations() async {
        await beginFileOperation(); defer { endFileOperation() }
        guard readable else { return }
        let files = RecordFileWorkspace(snapshot: state, snapshotURL: snapshotURL)
        do {
            let next = try await WorkoutFileIO.shared.perform { try files.enrichRetainedDurations() }
            if next.history != state.history { publish(next) }
        } catch { /* A failed enrichment never overwrites a readable record. */ }
    }

    func csv(records: [PhoneTrainingSession], sets: Bool, exercise: ExerciseType? = nil) -> String {
        func escaped(_ value: String) -> String {
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: value.hasPrefix) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let number: (Double) -> String = { String($0) }
        var rows = [sets ? ["record_id", "date", "exercise", "set", "reps", "weight_kg", "note"] : ["record_id", "date", "exercise", "reps", "max_weight_kg", "duration_seconds", "note"]]
        for item in records {
            if exercise != nil, item.workoutReport != nil, !item.reportMatchesCorrection { continue }
            let prefix = [item.id.uuidString, item.startTime.ISO8601Format()]
            if sets {
                if let report = item.workoutReport, item.reportMatchesCorrection {
                    for (index, set) in report.sets.enumerated() where exercise == nil || set.exercise == exercise {
                        let weights = Set(set.repetitions.map(\.weight))
                        rows.append(prefix + [set.exercise.rawValue, String(index + 1), String(set.totalReps), report.hasKnownWeights && weights.count == 1 ? number(weights.first!) : "", item.note ?? ""])
                    }
                } else {
                    for (index, set) in item.measuredSets.enumerated() where exercise == nil || set.exercise == exercise {
                        rows.append(prefix + [set.exercise.rawValue, String(index + 1), String(set.reps), number(set.weight), item.note ?? ""])
                    }
                }
            } else {
                let reps = item.repetitions(for: exercise)
                let weight = item.maximumWeight(for: exercise)
                rows.append(prefix + [(exercise.map { [$0] } ?? item.exercises).map(\.rawValue).joined(separator: ";"), String(reps), item.hasKnownWeight ? number(weight) : "", item.measuredActiveDuration(for: exercise).map(number) ?? "", item.note ?? ""])
            }
        }
        return "\u{FEFF}" + rows.map { $0.map(escaped).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}

private struct RecordFileWorkspace {
    let snapshot: RecordSnapshot
    let snapshotURL: URL
    private var state: RecordSnapshot { snapshot }
    private var history: [PhoneTrainingSession] { snapshot.history }
    private var timelineArchive: WorkoutTimelineArchive {
        WorkoutTimelineArchive(folder: snapshotURL.deletingLastPathComponent().appendingPathComponent("Timelines"))
    }
    private var reportSensorArchive: WorkoutReportSensorArchive {
        WorkoutReportSensorArchive(folder: snapshotURL.deletingLastPathComponent().appendingPathComponent("ReportSensors", isDirectory: true))
    }
    private func timeline(for id: UUID) throws -> WorkoutTimeline? {
        guard !snapshot.deletedIDs.contains(id), let record = history.first(where: { $0.id == id }),
              let result = try timelineArchive.load(id) else { return nil }
        try PhoneWorkoutStore.validate(result, for: record)
        return result
    }
    func backupData() throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeBackup(to: url)
        return try Data(contentsOf: url)
    }
    func writeBackup(to destination: URL) throws {
        let url = destination.deletingLastPathComponent().appendingPathComponent(".backup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let header = try JSONEncoder().encode(RecordBackup(snapshot: snapshot))
        guard header.last == 125 else { throw RecordFileError.invalid }
        try header.dropLast().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var count = header.count - 1
        func append(_ data: Data) throws {
            count += data.count
            guard count <= PhoneWorkoutStore.maximumBackupBytes else { throw RecordFileError.tooLarge }
            try handle.write(contentsOf: data)
        }
        try append(Data(",\"timelines\":[".utf8))
        var first = true
        for record in history {
            try autoreleasepool {
                guard let trace = try timeline(for: record.id) else { return }
                if !first { try append(Data([44])) }; first = false
                try append(JSONEncoder().encode(trace))
            }
        }
        try append(Data("],\"reportSensors\":[".utf8))
        first = true
        for record in history where record.sourceWorkoutReport != nil {
            let source = try PhoneWorkoutStore.reportSource(record)
            for segment in try reportSensorArchive.index(for: source) {
                try autoreleasepool {
                    guard let trace = try reportSensorArchive.load(workoutID: record.id, segmentID: segment.id) else { throw RecordFileError.invalid }
                    try WorkoutReportSensorArchive.validate(trace, for: source)
                    if !first { try append(Data([44])) }; first = false
                    try append(JSONEncoder().encode(RecordReportSensorBackup(workoutID: record.id, timeline: trace)))
                }
            }
        }
        try append(Data("]}".utf8))
        try handle.synchronize()
        try handle.close()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: url)
        } else { try FileManager.default.moveItem(at: url, to: destination) }
    }
    private func mergedDrafts(_ incoming: [RecordEditorDraft]) -> [RecordEditorDraft] {
        var result = snapshot.editorDrafts
        for draft in incoming {
            if let id = draft.recordID, snapshot.deletedIDs.contains(id) { continue }
            if !result.contains(where: { $0.id == draft.id || ($0.recordID != nil && $0.recordID == draft.recordID) }) { result.append(draft) }
        }
        return result
    }
    func acceptHistory(_ records: [WorkoutSync.Record]) throws -> RecordSnapshot {
        var traces: [UUID: WorkoutTimeline] = [:]
        for record in records where !snapshot.deletedIDs.contains(record.id) {
            if let trace = try timelineArchive.load(record.id) {
                guard PhoneWorkoutStore.compatible(trace.source, record) else { throw WorkoutSync.Failure.conflictingRecord }
                traces[record.id] = trace
            }
        }
        var next = snapshot
        try PhoneWorkoutStore.merge(records, into: &next)
        for trace in traces.values { _ = try PhoneWorkoutStore.enrichDuration(from: trace, into: &next) }
        return next
    }
    func acceptTimeline(_ data: Data, id: UUID) throws -> RecordSnapshot {
        guard data.count <= WorkoutTimeline.maximumFileBytes else { throw RecordFileError.invalid }
        let trace = try JSONDecoder().decode(WorkoutTimeline.self, from: data)
        try trace.validate()
        guard trace.id == id else { throw WorkoutSync.Failure.invalidPayload }
        if snapshot.deletedIDs.contains(id) { return snapshot }
        if let record = history.first(where: { $0.id == id }) { try PhoneWorkoutStore.validate(trace, for: record) }
        try timelineArchive.retain(trace)
        var next = snapshot
        if try PhoneWorkoutStore.enrichDuration(from: trace, into: &next) {
            try PhoneWorkoutStore.validate(next)
            try PhoneWorkoutStore.write(next, to: snapshotURL)
        }
        return next
    }
    private struct DurationCache: Codable {
        var version = BenchAnalysis.version + "/" + SquatStream.version + "/timing-1"
        var attempts: [UUID: String] = [:]
    }
    func enrichRetainedDurations() throws -> RecordSnapshot {
        let url = snapshotURL.deletingLastPathComponent().appendingPathComponent("duration-attempts-v1.json")
        let expected = DurationCache().version
        var cache = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DurationCache.self, from: $0) } ?? DurationCache()
        if cache.version != expected { cache = DurationCache() }
        let old = cache.attempts
        var next = snapshot
        for record in history {
            guard let source = record.watchSummary ?? record.legacySummary, source.activeDuration == nil else { continue }
            let file = timelineArchive.fileURL(record.id)
            do {
                let attributes = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let signature = "\(attributes.fileSize ?? 0)/\(attributes.contentModificationDate?.timeIntervalSince1970 ?? 0)/\(source.totalReps)/\(source.duration)"
                if cache.attempts[record.id] == signature { continue }
                guard let trace = try timelineArchive.load(record.id) else { continue }
                _ = try PhoneWorkoutStore.enrichDuration(from: trace, into: &next)
                cache.attempts[record.id] = signature
            } catch { /* Missing or unreadable traces remain retryable. */ }
        }
        if next.history != snapshot.history { try PhoneWorkoutStore.validate(next); try PhoneWorkoutStore.write(next, to: snapshotURL) }
        let present = Set(next.history.map(\.id))
        cache.attempts = cache.attempts.filter { present.contains($0.key) }
        if old != cache.attempts { try? JSONEncoder().encode(cache).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        return next
    }
    func restore(_ preview: RecordRestorePreview, readable: Bool) throws -> RecordSnapshot {
        // Recompute from current state: Watch batches may have arrived during preview.
        try PhoneWorkoutStore.validateBackup(preview.backup)
        var next = state
        let existing = Set(history.map(\.id)), blocked = existing.union(state.deletedIDs)
        let added = preview.backup.snapshot.history.filter { !blocked.contains($0.id) }
        let addedIDs = Set(added.map(\.id))
        next.history += added
        next.deletedIDs.formUnion(preview.backup.snapshot.deletedIDs.subtracting(existing))
        next.editorDrafts = mergedDrafts(preview.backup.snapshot.editorDrafts)
        if next.session == nil { next.session = preview.backup.snapshot.session }
        next.history.sort { $0.startTime > $1.startTime }
        try PhoneWorkoutStore.validate(next)
        if readable {
            try PhoneWorkoutStore.write(state, to: snapshotURL.deletingLastPathComponent().appendingPathComponent("before-restore.json"))
            try writeBackup(to: snapshotURL.deletingLastPathComponent().appendingPathComponent("before-restore-training-records.json"))
        } else if FileManager.default.fileExists(atPath: snapshotURL.path) {
            // Preserve the exact unreadable file before explicitly confirmed recovery.
            let original = snapshotURL.deletingLastPathComponent().appendingPathComponent("before-recovery-" + UUID().uuidString + ".json")
            try FileManager.default.copyItem(at: snapshotURL, to: original)
        }
        var newFiles: [UUID] = []
        var newSensorFiles: [URL] = []
        do {
            for timeline in preview.backup.timelines ?? [] where addedIDs.contains(timeline.id) {
                if let current = try timelineArchive.load(timeline.id) {
                    // A file received before its summary remains authoritative.
                    guard PhoneWorkoutStore.compatible(current.source, timeline.source) else { throw WorkoutSync.Failure.conflictingRecord }
                } else {
                    try timelineArchive.retain(timeline)
                    newFiles.append(timeline.id)
                }
            }
            let parents = Dictionary(uniqueKeysWithValues: added.map { ($0.id, $0) })
            for sensor in preview.backup.reportSensors ?? [] where addedIDs.contains(sensor.workoutID) {
                guard let record = parents[sensor.workoutID] else { throw RecordFileError.invalid }
                let source = try PhoneWorkoutStore.reportSource(record)
                if let current = try reportSensorArchive.load(workoutID: sensor.workoutID, segmentID: sensor.timeline.id) {
                    // Retained local data stays authoritative during a merge.
                    try WorkoutReportSensorArchive.validate(current, for: source)
                    guard PhoneWorkoutStore.compatible(current.source, sensor.timeline.source) else { throw WorkoutSync.Failure.conflictingRecord }
                } else {
                    try reportSensorArchive.retain(sensor.timeline, for: source)
                    newSensorFiles.append(reportSensorArchive.fileURL(workoutID: sensor.workoutID, segmentID: sensor.timeline.id))
                }
            }
            try PhoneWorkoutStore.write(next, to: snapshotURL)
            return next
        } catch {
            for id in newFiles { try? timelineArchive.remove(id) }
            for url in newSensorFiles { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}
