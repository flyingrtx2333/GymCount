import SwiftUI
import Charts

private func reportText(_ key: String) -> String {
    NSLocalizedString(key, tableName: "WholeWorkout", comment: "")
}

private func reportTime(_ seconds: TimeInterval) -> String {
    Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
}

// A report stays attached to its original Watch source. Corrections never rewrite
// recorded repetition times, health measurements, or the source set structure.
struct RecordWholeWorkoutReport: View {
    let report: WorkoutReport
    let totalReps: Int
    let maximumWeight: Double?
    let sourceMatches: Bool
    let history: [PhoneTrainingSession]
    let groupingEdited: Bool
    var saveGrouping: ([[UUID]]?) -> Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @ScaledMetric(relativeTo: .caption2) private var setLabelHeight: CGFloat = 24
    @State private var selectedSet: UUID?
    @State private var expandedSets = true
    @State private var expandedComparison = false
    @State private var splittingSet: WorkoutReport.SetRecord?
    @State private var groupingFailed = false

    private var exercises: [ExerciseType] {
        ExerciseType.allCases.filter { exercise in report.sets.contains { $0.exercise == exercise } }
    }
    private var selected: WorkoutReport.SetRecord? { report.sets.first { $0.id == selectedSet } }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2)
    }
    private var hasSecondarySummary: Bool {
        maximumWeight != nil || report.pauseDuration > 0 || report.activeEnergyKcal != nil ||
        (sourceMatches && (report.hasKnownWeights || (report.sets.count > 1 && report.intervalDuration != nil)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Studio.spacing) {
            timeSummary
            if hasSecondarySummary { secondarySummary }
            if sourceMatches, exercises.count > 1 { exerciseTotals }
            Divider().overlay(Studio.line)
            VStack(alignment: .leading, spacing: 8) {
                if !sourceMatches {
                    Text(reportText("Original set details")).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                }
                setsHeader
                setTimeline
                if expandedSets { setDetails }
            }
            if report.averageHeartRate != nil || report.maximumHeartRate != nil || !report.heartRates.isEmpty {
                Divider().overlay(Studio.line)
                heartRate
            }
            if sourceMatches, !comparisons.isEmpty {
                Divider().overlay(Studio.line)
                comparison
            }
        }.padding(.vertical, 8).accessibilityElement(children: .contain)
            .sheet(item: $splittingSet) { set in
                ReportSplitSheet(set: set) { position in
                    split(set, after: position)
                }
            }
            .alert(reportText("Could not save grouping"), isPresented: $groupingFailed) {
                Button(reportText("OK"), role: .cancel) { }
            }
    }

    private var timeSummary: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            RecordMetric(title: reportText("Repetitions"), value: String(localized: "\(totalReps) 次"))
                .accessibilityElement(children: .ignore).accessibilityLabel(String(localized: "总次数"))
                .accessibilityValue(String(localized: "\(totalReps) 次")).accessibilityIdentifier("record-total-reps")
            RecordMetric(title: String(localized: "训练时长"),
                         value: sourceMatches ? report.activeDuration.map(reportTime) ?? "—" : "—")
                .accessibilityIdentifier("report-training-duration")
        }
    }

    private var secondarySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sourceMatches, report.sets.count > 1, let interval = report.intervalDuration {
                summaryRow(reportText("Between sets"), value: reportTime(interval))
            }
            if report.pauseDuration > 0 {
                summaryRow(reportText("Paused"), value: reportTime(report.pauseDuration))
            }
            if let maximumWeight {
                summaryRow(reportText("Maximum load"), value: maximumWeight.formatted() + " " + reportText("Kilograms"))
            }
            if sourceMatches, report.hasKnownWeights {
                summaryRow(String(localized: "总训练量"), value: report.totalWeight.formatted() + " " + reportText("Kilograms"))
            }
            if let energy = report.activeEnergyKcal {
                summaryRow(reportText(report.metricsComplete ? "Active energy · estimated" : "Recorded active energy"),
                           value: energy.formatted(.number.precision(.fractionLength(0))) + " kcal")
                    .accessibilityIdentifier("report-active-energy")
            }
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        (typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))) {
            Text(title).foregroundStyle(Studio.muted)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(value).foregroundStyle(Studio.ink).monospacedDigit()
        }.font(Studio.Fonts.caption).accessibilityElement(children: .combine)
    }

    private var setsHeader: some View {
        (typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 8))) {
            Text(reportText("Sets & timeline")).font(Studio.Fonts.section)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("whole-workout-report")
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            HStack(spacing: 0) {
                if selected != nil {
                    Button { selectedSet = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(RecordPressStyle()).accessibilityLabel(reportText("Show full session"))
                        .accessibilityIdentifier("report-clear-set")
                }
                if groupingEdited {
                    Menu {
                        Button(reportText("Restore automatic grouping")) {
                            if !saveGrouping(nil) { groupingFailed = true }
                        }.accessibilityIdentifier("report-reset-grouping")
                    } label: {
                        Image(systemName: "ellipsis").font(Studio.Fonts.body)
                            .frame(width: Studio.controlHeight, height: Studio.controlHeight)
                    }.accessibilityLabel(reportText("Edit set grouping"))
                        .accessibilityIdentifier("report-grouping-options")
                }
                Button {
                    withAnimation(RecordMotion.animation(reduced: reducedMotion)) { expandedSets.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(setCount(report.sets.count))
                            .foregroundStyle(Studio.muted).accessibilityIdentifier("report-set-count")
                        Image(systemName: expandedSets ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                }.buttonStyle(RecordPressStyle()).accessibilityIdentifier("report-sets-heading")
                    .accessibilityHint(reportText(expandedSets ? "Collapse sets" : "Expand sets"))
            }.frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
        }
    }

    private var exerciseTotals: some View {
        VStack(spacing: 8) {
            ForEach(exercises, id: \.self) { exercise in
                let sets = report.sets.filter { $0.exercise == exercise }
                HStack(spacing: 8) {
                    RecordExerciseLabel(exercise: exercise, size: 22)
                    Text(setCount(sets.count)).foregroundStyle(Studio.muted)
                    Spacer(minLength: 8)
                    Text(String(localized: "\(sets.reduce(0) { $0 + $1.totalReps }) 次")).monospacedDigit()
                }.font(Studio.Fonts.body)
            }
        }
    }

    private var setTimeline: some View {
        let sets = selected.map { [$0] } ?? report.sets
        let strideSize = selected == nil ? max(1, Int(ceil(Double(report.totalReps) / 360))) : 1
        let lower = selected?.startedAt ?? report.startedAt
        let upper = max(selected?.endedAt ?? report.endedAt, lower.addingTimeInterval(1))
        let axisDates = timeAxisDates(from: lower, to: upper)
        let visibleExercises = Set(sets.map(\.exercise)).count
        let visiblePauses = report.pauses.filter { $0.endedAt > lower && $0.startedAt < upper }
        let regions = RecordSetRegion.make(sets: report.sets, origin: report.startedAt)
            .filter { selectedSet == nil || selectedSet == $0.id || selected == nil }
        let visible = lower.timeIntervalSince(report.startedAt)...upper.timeIntervalSince(report.startedAt)
        return Chart {
                ForEach(sets) { set in
                    if let first = set.repetitions.first?.completedAt, let last = set.repetitions.last?.completedAt, last > first {
                        RectangleMark(xStart: .value("First completion", first), xEnd: .value("Last completion", last),
                                      y: .value("Exercise", set.exercise.recordName), height: .fixed(2))
                            .foregroundStyle(Studio.accent.opacity(0.5))
                            .accessibilityLabel(set.exercise.recordName)
                            .accessibilityValue(String(localized: "\(set.totalReps) 次"))
                    }
                    ForEach(set.repetitions.enumerated().filter { $0.offset % strideSize == 0 || $0.offset == set.totalReps - 1 }.map(\.element)) { rep in
                        PointMark(x: .value("Completion", rep.completedAt), y: .value("Exercise", set.exercise.recordName))
                            .symbolSize(10).foregroundStyle(Studio.ink)
                            .accessibilityLabel(rep.completedAt.formatted(date: .omitted, time: .standard))
                    }
                }
                ForEach(Array(visiblePauses.enumerated()), id: \.offset) { _, pause in
                    RectangleMark(xStart: .value("Start", pause.startedAt), xEnd: .value("End", pause.endedAt),
                                  y: .value("Exercise", reportText("Paused")), height: .fixed(8))
                        .foregroundStyle(Studio.muted.opacity(0.4))
                }
            }
            .chartXScale(domain: lower...upper, range: .plotDimension(startPadding: 0, endPadding: 0))
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        RecordSetRegionBackdrop(regions: regions, visible: visible,
                                                plotFrame: geometry[anchor], labelHeight: setLabelHeight)
                    }
                }.allowsHitTesting(false)
            }
            .chartXAxis { timeAxis(axisDates) }
            .chartYAxis {
                if visibleExercises > 1 || !visiblePauses.isEmpty {
                    AxisMarks { _ in AxisValueLabel().font(Studio.Fonts.axis) }
                }
            }
            .frame(height: CGFloat(visibleExercises + (visiblePauses.isEmpty ? 0 : 1)) * 34 + 32)
            .padding(.top, regions.isEmpty ? 0 : setLabelHeight)
            .accessibilityValue(regions.map {
                "\($0.title), \(reportTime($0.firstCompletion)) – \(reportTime($0.lastCompletion))"
            }.joined(separator: "; "))
            .accessibilityIdentifier("report-set-timeline")
    }

    private var setDetails: some View {
        VStack(spacing: 0) {
                ForEach(Array(report.sets.enumerated()), id: \.element.id) { index, set in
                    if index > 0, let gap = gap(before: index), gap > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "clock").accessibilityHidden(true)
                            Text(reportTime(gap)).monospacedDigit()
                            Rectangle().fill(Studio.line).frame(height: Studio.hairline).accessibilityHidden(true)
                        }.font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            .accessibilityElement(children: .ignore).accessibilityLabel(reportText("Between sets"))
                            .accessibilityValue(reportTime(gap))
                    }
                    HStack(spacing: 0) {
                    Button { selectedSet = selectedSet == set.id ? nil : set.id } label: {
                        HStack(spacing: 10) {
                            if exercises.count > 1 { RecordExerciseIcon(exercise: set.exercise, size: 24) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercises.count > 1 ? set.exercise.recordName : setName(index))
                                    .font(Studio.Fonts.body.weight(.medium))
                                let metadata = setMetadata(set, index: index)
                                if !metadata.isEmpty {
                                    Text(metadata).font(Studio.Fonts.caption).foregroundStyle(Studio.muted).monospacedDigit()
                                        .accessibilityLabel(setMetadata(set, index: index, accessible: true))
                                }
                            }
                            Spacer(minLength: 8)
                            Text(String(localized: "\(set.totalReps) 次")).font(Studio.Fonts.rowMetric).monospacedDigit()
                                .fixedSize(horizontal: true, vertical: false)
                        }.foregroundStyle(Studio.ink).frame(minHeight: Studio.controlHeight)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("report-set-\(index + 1)")
                        .accessibilityElement(children: .combine)
                    if sourceMatches, set.totalReps > 1 || (index > 0 && report.sets[index - 1].exercise == set.exercise) {
                        Menu {
                            if index > 0, report.sets[index - 1].exercise == set.exercise {
                                Button(reportText("Merge with previous set")) { merge(at: index) }.accessibilityIdentifier("report-merge-previous")
                            }
                            if set.totalReps > 1 {
                                Button(reportText("Split set")) { splittingSet = set }.accessibilityIdentifier("report-split-set")
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(Studio.Fonts.body)
                                .frame(width: Studio.controlHeight, height: Studio.controlHeight)
                        }.accessibilityLabel(reportText("Edit set grouping"))
                            .accessibilityIdentifier("report-set-menu-\(index + 1)")
                    } else {
                        Color.clear.frame(width: Studio.controlHeight, height: Studio.controlHeight).accessibilityHidden(true)
                    }
                    }.padding(.vertical, 6)
                        .background(selectedSet == set.id ? Studio.accent.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Studio.controlRadius))
                }
        }.padding(.top, 4).tint(Studio.accent)
    }

    private func setName(_ index: Int) -> String {
        String(format: reportText("Set %ld"), index + 1)
    }

    private func setCount(_ count: Int) -> String {
        String(count) + " " + reportText(count == 1 ? "set" : "sets")
    }

    private func setMetadata(_ set: WorkoutReport.SetRecord, index: Int, accessible: Bool = false) -> String {
        var parts: [String] = []
        if exercises.count > 1 { parts.append(setName(index)) }
        if report.hasKnownWeights { parts.append(weightText(set)) }
        if let active = set.activeDuration {
            parts.append((accessible ? String(localized: "训练时长") + " " : "") + reportTime(active))
        }
        return parts.joined(separator: " · ")
    }

    private var heartRate: some View {
        let points = heartRatePoints
        let upper = max(report.endedAt, report.startedAt.addingTimeInterval(1))
        let axisDates = timeAxisDates(from: report.startedAt, to: upper)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(reportText("Heart rate")).font(Studio.Fonts.section)
                Spacer()
                Text("bpm").font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
            }
            HStack(spacing: 24) {
                if let average = report.averageHeartRate { RecordMetric(title: reportText("Average"), value: average.formatted(.number.precision(.fractionLength(0)))) }
                if let maximum = report.maximumHeartRate { RecordMetric(title: reportText("Peak"), value: maximum.formatted(.number.precision(.fractionLength(0)))) }
            }
            if !points.isEmpty {
            Chart {
                ForEach(points, id: \.index) { sample in
                    let point = sample.point
                    // Do not draw a continuous heart-rate curve across a missing interval.
                    LineMark(x: .value("Time", point.date), y: .value("BPM", point.bpm), series: .value("Segment", sample.segment))
                        .foregroundStyle(Studio.accent).lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(x: .value("Time", point.date), y: .value("BPM", point.bpm)).symbolSize(7).foregroundStyle(Studio.accent)
                }
            }.chartXScale(domain: report.startedAt...upper)
                .chartXAxis { timeAxis(axisDates) }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .frame(height: 120).accessibilityIdentifier("report-heart-rate")
            }
        }
    }

    private var comparison: some View {
        DisclosureGroup(isExpanded: $expandedComparison) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(comparisons, id: \.exercise) { value in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            RecordExerciseLabel(exercise: value.exercise, size: 20).font(Studio.Fonts.body.weight(.medium))
                            Spacer(minLength: 8)
                            Text(value.previousDate.formatted(date: .abbreviated, time: .omitted)).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                        }
                        summaryRow(reportText("Repetitions"), value: String(value.previousReps) + " → " + String(value.currentReps))
                        if let previous = value.previousWeight, let current = value.currentWeight {
                            summaryRow(reportText("Maximum load"), value: previous.formatted() + " → " + current.formatted() + " " + reportText("Kilograms"))
                        }
                        if let change = value.intervalChange, abs(change) >= 1 {
                            summaryRow(reportText("Average interval"), value: (change > 0 ? "+" : "−") + reportTime(abs(change)))
                        }
                        if value.sameLoadsAndSets, value.currentReps < value.previousReps {
                            Text(reportText("Keep the same load and compare your next session."))
                                .font(Studio.Fonts.caption).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }.padding(.top, 10)
        } label: {
            Text(reportText("Compared with last session")).font(Studio.Fonts.section)
        }.tint(Studio.accent).accessibilityIdentifier("report-comparison")
    }

    private func timeAxisDates(from start: Date, to end: Date) -> [Date] {
        let duration = end.timeIntervalSince(start)
        guard duration > 2 else { return [start, end] }
        return [start, start.addingTimeInterval(duration / 2), end]
    }
    private func timeAxis(_ dates: [Date]) -> some AxisContent {
        AxisMarks(values: dates) { value in
            AxisGridLine().foregroundStyle(Studio.line)
            if let date = value.as(Date.self) {
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == dates.count - 1 ? .topTrailing : .top) {
                    Text(reportTime(date.timeIntervalSince(report.startedAt)))
                        .font(Studio.Fonts.axis).monospacedDigit().fixedSize()
                }
            }
        }
    }

    private func merge(at index: Int) {
        var groups = report.sets.map { $0.repetitions.map(\.id) }
        let next = groups.remove(at: index)
        groups[index - 1].append(contentsOf: next)
        if !saveGrouping(groups) { groupingFailed = true }
    }
    private func split(_ set: WorkoutReport.SetRecord, after position: Int) -> Bool {
        guard let index = report.sets.firstIndex(where: { $0.id == set.id }), position > 0, position < set.totalReps else { return false }
        var groups = report.sets.map { $0.repetitions.map(\.id) }
        let ids = groups.remove(at: index)
        groups.insert(contentsOf: [Array(ids.prefix(position)), Array(ids.dropFirst(position))], at: index)
        return saveGrouping(groups)
    }
    private var comparisons: [WholeWorkoutComparison] {
        exercises.compactMap { WholeWorkoutComparison(exercise: $0, current: report, history: history) }
    }
    private func weightText(_ set: WorkoutReport.SetRecord) -> String {
        let weights = set.repetitions.map(\.weight)
        guard let low = weights.min(), let high = weights.max() else { return "" }
        let value = low == high ? high.formatted() : low.formatted() + "–" + high.formatted()
        return value + " " + reportText("Kilograms")
    }
    private func gap(before index: Int) -> TimeInterval? {
        guard index > 0, report.sets[index].repetitions.first?.startedAt != nil else { return nil }
        let start = report.sets[index - 1].endedAt, end = report.sets[index].startedAt
        let paused = report.pauses.reduce(0.0) { $0 + max(0, min(end, $1.endedAt).timeIntervalSince(max(start, $1.startedAt))) }
        return max(0, end.timeIntervalSince(start) - paused)
    }
    private var heartRatePoints: [(index: Int, point: WorkoutReport.HeartRatePoint, segment: Int)] {
        var segment = 0
        let all = report.heartRates.sorted { $0.date < $1.date }
        let segmented = all.enumerated().map { index, point in
            if index > 0, point.date.timeIntervalSince(all[index - 1].date) > 30 { segment += 1 }
            return (index: index, point: point, segment: segment)
        }
        guard segmented.count > 360 else { return segmented }
        let size = Int(ceil(Double(segmented.count) / 120))
        var kept = Set([0, segmented.count - 1])
        for start in stride(from: 0, to: segmented.count, by: size) {
            let bucket = segmented[start..<min(start + size, segmented.count)]
            if let min = bucket.min(by: { $0.point.bpm < $1.point.bpm }) { kept.insert(min.index) }
            if let max = bucket.max(by: { $0.point.bpm < $1.point.bpm }) { kept.insert(max.index) }
        }
        return kept.sorted().map { segmented[$0] }
    }

}

private struct WholeWorkoutComparison {
    let exercise: ExerciseType
    let previousDate: Date
    let previousReps: Int
    let currentReps: Int
    let sameLoadsAndSets: Bool
    let previousWeight: Double?
    let currentWeight: Double?
    let intervalChange: TimeInterval?

    init?(exercise: ExerciseType, current: WorkoutReport, history: [PhoneTrainingSession]) {
        guard let prior = history.filter({ $0.startTime < current.startedAt && $0.reportMatchesCorrection && $0.exercises.contains(exercise) })
            .sorted(by: { $0.startTime > $1.startTime }).first(where: { $0.workoutReport != nil }),
              let previous = prior.workoutReport else { return nil }
        let currentSets = current.sets.filter { $0.exercise == exercise }
        let previousSets = previous.sets.filter { $0.exercise == exercise }
        guard !currentSets.isEmpty, !previousSets.isEmpty else { return nil }
        self.exercise = exercise; previousDate = prior.startTime
        currentReps = currentSets.reduce(0) { $0 + $1.totalReps }
        previousReps = previousSets.reduce(0) { $0 + $1.totalReps }
        previousWeight = previous.hasKnownWeights ? previousSets.map(\.maxWeight).max() : nil
        currentWeight = current.hasKnownWeights ? currentSets.map(\.maxWeight).max() : nil
        sameLoadsAndSets = current.hasKnownWeights && previous.hasKnownWeights && currentSets.count == previousSets.count && zip(currentSets, previousSets).allSatisfy { a, b in
            Set(a.repetitions.map(\.weight)) == Set(b.repetitions.map(\.weight))
        }
        func averageGap(_ report: WorkoutReport, _ sets: [WorkoutReport.SetRecord]) -> TimeInterval? {
            guard sets.count > 1 else { return nil }
            var values: [TimeInterval] = []
            for index in 1..<sets.count {
                let a = sets[index - 1], b = sets[index]
                guard b.repetitions.first?.startedAt != nil,
                      let fullIndex = report.sets.firstIndex(where: { $0.id == b.id }), fullIndex > 0,
                      report.sets[fullIndex - 1].id == a.id else { return nil }
                let paused = report.pauses.reduce(0.0) { $0 + max(0, min(b.startedAt, $1.endedAt).timeIntervalSince(max(a.endedAt, $1.startedAt))) }
                values.append(max(0, b.startedAt.timeIntervalSince(a.endedAt) - paused))
            }
            return values.reduce(0, +) / Double(values.count)
        }
        if let a = averageGap(current, currentSets), let b = averageGap(previous, previousSets) { intervalChange = a - b }
        else { intervalChange = nil }
    }
}

private struct ReportSplitSheet: View {
    let set: WorkoutReport.SetRecord
    var save: (Int) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var position = 1
    @State private var failed = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $position, in: 1...(set.totalReps - 1)) {
                        LabeledContent(reportText("First set repetitions"), value: String(position))
                    }.accessibilityIdentifier("report-split-position")
                    LabeledContent(reportText("Second set repetitions"), value: String(set.totalReps - position))
                }.listRowBackground(Studio.surface)
                if failed { Text(reportText("Could not save grouping")).foregroundStyle(.red) }
            }.recordListStyle().navigationTitle(reportText("Split set")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "保存")) {
                            if save(position) { dismiss() } else { failed = true }
                        }.accessibilityIdentifier("report-split-save")
                    }
                }
        }
    }
}
