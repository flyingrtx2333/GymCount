import SwiftUI
import Charts

// One restrained overview, followed by distributions and the existing time series.
// All sections consume the same filtered snapshot.
struct RecordTrainingOverview: View {
    let insights: RecordTrainingInsights
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : typeSize >= .xLarge ? 2 : 4
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: columns), alignment: .leading, spacing: 12) {
            value(String(localized: "记录"), String(localized: "\(insights.sessionCount) 条"), displayValue: insights.sessionCount.formatted(), id: "insights-records")
            value(String(localized: "次数"), String(localized: "\(insights.totalReps) 次"), displayValue: insights.totalReps.formatted(), id: "insights-reps")
            value(String(localized: "天数"), String(localized: "\(insights.trainingDays) 天"), displayValue: insights.trainingDays.formatted(), id: "insights-days")
            value(String(localized: "训练时长"), insights.knownDuration.map(RecordTrendMetric.clock) ?? "—", id: "insights-duration")
        }.foregroundStyle(Studio.ink).accessibilityElement(children: .contain).accessibilityIdentifier("training-overview")
    }
    private func value(_ title: String, _ value: String, displayValue: String? = nil, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
            RecordNumberText(value: displayValue ?? value, numberFont: Studio.Fonts.metric, unitFont: Studio.Fonts.caption)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(value)
            .accessibilityIdentifier(id)
    }
}

struct RecordExerciseDistribution: View {
    let insights: RecordTrainingInsights
    let selectExercise: (ExerciseType) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showReps = false
    private var sectors: [RecordTrainingInsights.ExerciseBreakdown] {
        insights.exerciseBreakdown.filter { count($0) > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())) {
                Text(String(localized: "动作")).font(Studio.Fonts.section)
                if !typeSize.isAccessibilitySize { Spacer() }
                Menu {
                    Button(String(localized: "按记录数")) { showReps = false }
                    Button(String(localized: "按动作次数")) { showReps = true }
                } label: {
                    HStack(spacing: 5) { Text(showReps ? String(localized: "次数") : String(localized: "记录")); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
                        .font(Studio.Fonts.control).frame(minHeight: Studio.controlHeight)
                }.accessibilityIdentifier("insights-exercise-metric")
            }
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 24))) {
                donut
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(insights.exerciseBreakdown) { row in
                        Button { selectExercise(row.exercise) } label: {
                            HStack(spacing: 8) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 8) {
                                        RecordExerciseLabel(exercise: row.exercise, size: 24, color: color(for: row.exercise))
                                            .font(Studio.Fonts.body.weight(.medium)).foregroundStyle(Studio.ink)
                                        Spacer(minLength: 8)
                                        frequency(row)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        RecordExerciseLabel(exercise: row.exercise, size: 24, color: color(for: row.exercise))
                                            .font(Studio.Fonts.body.weight(.medium)).foregroundStyle(Studio.ink)
                                        frequency(row)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 4).frame(maxWidth: .infinity, minHeight: Studio.controlHeight, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(RecordPressStyle())
                            .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
                            .accessibilityLabel(row.exercise.recordName)
                            .accessibilityValue(String(localized: "\(row.recordCount) 条 · \(row.reps) 次"))
                            .accessibilityHint(String(localized: "筛选此动作"))
                            .accessibilityIdentifier("insights-exercise-\(row.exercise.rawValue)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("exercise-distribution")
    }

    private var donut: some View {
        ZStack {
            Circle().stroke(Studio.line, lineWidth: 9).padding(4.5)
            if !sectors.isEmpty {
                Chart(sectors) { row in
                    SectorMark(angle: .value(showReps ? String(localized: "次数") : String(localized: "记录数"), count(row)),
                               innerRadius: .ratio(0.83), outerRadius: .ratio(1),
                               angularInset: sectors.count > 1 ? 2 : 0)
                        .foregroundStyle(color(for: row.exercise))
                        .cornerRadius(1.5)
                }.chartLegend(.hidden)
                    // Replacing sectors must not interpolate removed slices
                    // through an invalid zero-total pie inside Swift Charts.
                    .id(sectors.map { "\($0.exercise.rawValue):\(count($0))" }.joined(separator: ","))
                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
            }
        }.frame(width: 104, height: 104)
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func count(_ row: RecordTrainingInsights.ExerciseBreakdown) -> Int {
        showReps ? row.reps : row.recordCount
    }

    private func color(for exercise: ExerciseType) -> Color {
        switch exercise {
        case .benchPress: Studio.accent
        case .squat: Studio.adaptive(0x1D7A72, 0x66C9BA)
        case .deadlift: Studio.adaptive(0x426BAE, 0x7AA8E5)
        case .overheadPress: Studio.adaptive(0xB35A36, 0xECA47F)
        case .barbellRow: Studio.adaptive(0x8058A5, 0xBB9ADA)
        case .bicepCurl: Studio.adaptive(0xB04972, 0xE994BA)
        }
    }
    private func frequency(_ row: RecordTrainingInsights.ExerciseBreakdown) -> some View {
        Text(showReps ? String(localized: "\(row.reps) 次") : String(localized: "\(row.recordCount) 条"))
            .font(Studio.Fonts.caption.monospacedDigit()).foregroundStyle(Studio.muted)
    }
}

struct RecordWeightDistribution: View {
    let insights: RecordTrainingInsights
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedWeight: Double?
    @State private var selectedLabel: String?
    private struct Point: Identifiable {
        let weight: Double
        let count: Int
        var id: Double { weight }
        var category: String { String(weight) }
        var label: String { weight.formatted(.number.grouping(.never).precision(.significantDigits(1...16))) }
    }
    private var bySets: Bool { !insights.weightBreakdown.isEmpty }
    private var points: [Point] {
        let input = bySets
            ? insights.weightBreakdown.map { Point(weight: $0.weight, count: $0.sets) }
            : insights.maximumWeightBreakdown.filter { $0.weight > 0 }.map { Point(weight: $0.weight, count: $0.recordCount) }
        // Show the most frequent eight loads, ordered by load on the chart.
        return Array(input.prefix(8)).sorted { $0.weight < $1.weight }
    }
    private var selected: Point? { points.first { $0.weight == selectedWeight } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { heading; Spacer(minLength: 12); Text(String(localized: "公斤")).font(Studio.Fonts.caption).foregroundStyle(Studio.muted) }
                VStack(alignment: .leading, spacing: 4) { heading; Text(String(localized: "公斤")).font(Studio.Fonts.caption).foregroundStyle(Studio.muted) }
            }
            if points.isEmpty {
                RecordInlineState(title: String(localized: "暂无重量记录"), systemImage: "scalemass")
            } else {
                Chart(points) { point in
                    BarMark(x: .value(String(localized: "重量"), point.category), y: .value(bySets ? String(localized: "组数") : String(localized: "记录数"), point.count))
                        .cornerRadius(3).foregroundStyle(Studio.accent.opacity(selected == nil || selected?.id == point.id ? 0.9 : 0.3))
                        .accessibilityLabel(String(localized: "\(point.weight.formatted()) 公斤"))
                        .accessibilityValue(bySets ? String(localized: "\(point.count) 组") : String(localized: "\(point.count) 条"))
                }.chartXSelection(value: $selectedLabel)
                    .chartGesture { proxy in
                        SpatialTapGesture().onEnded { event in proxy.selectXValue(at: event.location.x) }
                    }
                    .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: Studio.hairline)).foregroundStyle(Studio.line.opacity(0.65))
                        AxisValueLabel { if let value = value.as(Int.self) { Text(value.formatted()) } }
                    }
                }.chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let category = value.as(String.self), let point = points.first(where: { $0.category == category }) {
                                Text(point.weight, format: .number.precision(.fractionLength(0...2))).foregroundStyle(Studio.muted)
                            }
                        }
                    }
                }
                    .frame(height: 112).font(Studio.Fonts.axis).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityIdentifier("insights-weight-chart")
                if let selected {
                    HStack {
                        Text(String(localized: "\(selected.weight.formatted()) 公斤"))
                        Spacer(minLength: 8)
                        Text(bySets ? String(localized: "\(selected.count) 组") : String(localized: "\(selected.count) 条"))
                        Button { selectedWeight = nil; selectedLabel = nil } label: { Image(systemName: "xmark").frame(width: Studio.controlHeight, height: Studio.controlHeight) }
                            .accessibilityLabel(String(localized: "清除选择"))
                    }.font(Studio.Fonts.body.monospacedDigit()).foregroundStyle(Studio.muted)
                }
                // Native buttons provide large, precise targets for a categorical
                // distribution, including VoiceOver and a single recorded load.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { weightButtons }
                    ScrollView(.horizontal) { HStack(spacing: 12) { weightButtons } }.scrollIndicators(.hidden)
                }
            }
        }.onChange(of: points.map(\.id)) { _, _ in selectedWeight = nil; selectedLabel = nil }
            .onChange(of: selectedLabel) { _, label in
                if let label { selectedWeight = points.first { $0.category == label }?.weight }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("weight-distribution")
    }
    private var heading: some View { Text(bySets ? String(localized: "常用重量") : String(localized: "最大重量")).font(Studio.Fonts.section) }
    @ViewBuilder private var weightButtons: some View {
        ForEach(points) { point in
            Button { selectedWeight = point.weight; selectedLabel = point.category } label: {
                Text(String(localized: "\(point.weight.formatted()) 公斤"))
                    .font(Studio.Fonts.caption.monospacedDigit()).padding(.horizontal, 4).frame(minHeight: Studio.controlHeight)
                    .foregroundStyle(selectedWeight == point.weight ? Studio.accent : Studio.muted)
            }.buttonStyle(RecordPressStyle()).fixedSize(horizontal: true, vertical: false)
                .accessibilityValue(bySets ? String(localized: "\(point.count) 组") : String(localized: "\(point.count) 条"))
                .accessibilityAddTraits(selectedWeight == point.weight ? .isSelected : [])
                .accessibilityIdentifier("insights-weight-\(point.label)")
        }
    }
}
