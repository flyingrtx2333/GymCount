import SwiftUI
import Charts

private struct RecordTrendPoint: Identifiable {
    let id: Date
    let sessions: Int
    let reps: Int
    let weight: Double
}

struct RecordTrendsView: View {
    @EnvironmentObject private var store: PhoneWorkoutStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var openDay: (ExerciseType, Date) -> Void
    @State private var filter = RecordFilter(exercise: .benchPress, period: .month)
    @State private var showReps = false
    @State private var selectedDate: Date?
    @State private var showDates = false
    private var points: [RecordTrendPoint] {
        Dictionary(grouping: store.history.filter(filter.includes), by: { Calendar.current.startOfDay(for: $0.startTime) }).map { day, rows in
            RecordTrendPoint(id: day, sessions: rows.count, reps: rows.reduce(0) { $0 + filter.reps($1) }, weight: rows.map(filter.weight).max() ?? 0)
        }.sorted { $0.id < $1.id }
    }
    private var selected: RecordTrendPoint? {
        guard let selectedDate else { return points.last }
        return points.min { abs($0.id.timeIntervalSince(selectedDate)) < abs($1.id.timeIntervalSince(selectedDate)) }
    }
    private var domain: ClosedRange<Date> {
        let first = points.first?.id ?? Date(), last = points.last?.id ?? Date()
        let padding: TimeInterval = max(86400, last.timeIntervalSince(first) * 0.04)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack { Text(String(localized: "趋势")).font(.title2.weight(.semibold)); Spacer() }
                    .padding(.horizontal, 20).frame(minHeight: 56)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if points.isEmpty {
                            ContentUnavailableView(String(localized: "暂无记录"), systemImage: "chart.xyaxis.line")
                                .frame(maxWidth: .infinity)
                        } else {
                            if let selected { selectedDay(selected) }
                            chart
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 8) {
                                    if let exercise = filter.exercise { RecordExerciseIcon(exercise: exercise, size: 24) }
                                    Text((filter.exercise?.recordName ?? "") + " · " + filter.rangeTitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                }.font(.subheadline.weight(.medium))
                                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                                layout { metrics }
                            }
                            Text(String(localized: "每日记录")).font(.headline)
                            LazyVStack(spacing: 0) {
                                ForEach(points.reversed()) { point in
                                    Button { openDay(filter.exercise ?? .benchPress, point.id) } label: {
                                        ViewThatFits(in: .horizontal) {
                                            HStack { Text(recordDate(point.id)); Spacer(minLength: 8); dailyValue(point); Image(systemName: "chevron.right").font(.caption) }
                                            VStack(alignment: .leading, spacing: 4) { Text(recordDate(point.id)); dailyValue(point) }
                                        }.font(.subheadline).frame(minHeight: 56).contentShape(Rectangle()).foregroundStyle(Studio.ink)
                                    }.buttonStyle(RecordPressStyle())
                                        .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: 0.5) }
                                }
                            }
                        }
                    }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
                }
            }.background(Studio.background)
                .safeAreaInset(edge: .bottom, spacing: 0) { filters }
                .toolbar(.hidden, for: .navigationBar)
                .animation(RecordMotion.animation(reduced: reduceMotion), value: filter)
                .onChange(of: filter) { _, _ in selectedDate = nil }
                .sheet(isPresented: $showDates) {
                    RecordDateSheet(singleDay: false, apply: { a, b in filter.start = a; filter.end = b; filter.period = .custom }, start: filter.start, end: filter.end)
                }
        }
    }
    private var filters: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            Menu {
                Picker(String(localized: "动作"), selection: $filter.exercise) {
                    ForEach(ExerciseType.allCases, id: \.self) { Label($0.recordName, image: $0.icon).tag(Optional($0)) }
                }
            } label: { RecordFilterLabel(title: filter.exercise?.recordName ?? String(localized: "全部动作"), exercise: filter.exercise).frame(maxWidth: .infinity) }
                .accessibilityIdentifier("trend-exercise-filter")
            if !typeSize.isAccessibilitySize { Divider().frame(height: 20) }
            Menu {
                ForEach([RecordFilter.Period.month, .quarter, .all], id: \.self) { period in Button(period.title) { filter.period = period } }
                Button(String(localized: "自定义日期")) { showDates = true }
            } label: { RecordFilterLabel(title: filter.period.title).frame(maxWidth: .infinity) }
                .accessibilityIdentifier("trend-period-filter")
            if !typeSize.isAccessibilitySize { Divider().frame(height: 20) }
            Menu {
                Button(String(localized: "最大重量")) { showReps = false }
                Button(String(localized: "次数")) { showReps = true }
            } label: { RecordFilterLabel(title: showReps ? String(localized: "次数") : String(localized: "最大重量")).frame(maxWidth: .infinity) }
                .accessibilityIdentifier("trend-metric")
        }.buttonStyle(RecordPressStyle()).padding(.horizontal, 12).padding(.vertical, 5).background(Studio.background)
            .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 0.5) }
    }
    private func selectedDay(_ point: RecordTrendPoint) -> some View {
        Button { openDay(filter.exercise ?? .benchPress, point.id) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(showReps ? String(localized: "\(point.reps) 次") : String(localized: "\(point.weight.formatted()) 公斤"))
                        .font(.title.weight(.semibold)).monospacedDigit().contentTransition(.numericText()).foregroundStyle(Studio.ink)
                    Text(recordDate(point.id)).font(.caption).foregroundStyle(Studio.muted)
                }
                Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(Studio.accent).accessibilityHidden(true)
                Spacer(minLength: 0)
            }.frame(minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(RecordPressStyle()).accessibilityHint(String(localized: "查看当天记录")).accessibilityIdentifier("trend-open-day")
    }
    private var chart: some View {
        Chart(points) { point in
            if showReps {
                BarMark(x: .value(String(localized: "日期"), point.id), y: .value(String(localized: "次数"), point.reps), width: .fixed(14))
                    .cornerRadius(3).opacity(selected?.id == point.id ? 1 : 0.55)
            } else {
                LineMark(x: .value(String(localized: "日期"), point.id), y: .value(String(localized: "公斤"), point.weight))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value(String(localized: "日期"), point.id), y: .value(String(localized: "公斤"), point.weight))
                    .symbolSize(selected?.id == point.id ? 65 : 22)
            }
            if selected?.id == point.id {
                RuleMark(x: .value(String(localized: "日期"), point.id))
                    .foregroundStyle(Studio.line).lineStyle(StrokeStyle(dash: [3, 4]))
            }
        }.foregroundStyle(Studio.accent)
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in
                    withAnimation(RecordMotion.animation(reduced: reduceMotion)) { proxy.selectXValue(at: event.location.x) }
                }.simultaneously(with: DragGesture(minimumDistance: 1).onChanged { proxy.selectXValue(at: $0.location.x) })
            }
            .chartXScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: [domain.lowerBound, domain.lowerBound.addingTimeInterval(domain.upperBound.timeIntervalSince(domain.lowerBound) / 2), domain.upperBound]) { value in
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == 2 ? .topTrailing : .top) {
                        if let date = value.as(Date.self) {
                            Text(date, format: Calendar.current.component(.year, from: domain.upperBound) != Calendar.current.component(.year, from: domain.lowerBound) ? .dateTime.year(.twoDigits).month(.twoDigits) : .dateTime.month(.twoDigits).day(.twoDigits)).fixedSize()
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Studio.line)
                    AxisValueLabel()
                }
            }
            .frame(height: 205)
            .accessibilityLabel(showReps ? String(localized: "每日次数") : String(localized: "每日最高重量")).accessibilityIdentifier("trend-chart")
            .animation(RecordMotion.animation(reduced: reduceMotion), value: showReps)
            .animation(RecordMotion.animation(reduced: reduceMotion), value: selected?.id)
    }
    private var metrics: some View {
        Group {
            RecordOverviewMetric(title: String(localized: "训练"), value: "\(points.reduce(0) { $0 + $1.sessions })")
            RecordOverviewMetric(title: String(localized: "累计次数"), value: "\(points.reduce(0) { $0 + $1.reps })")
                .accessibilityElement(children: .ignore).accessibilityLabel(String(localized: "累计次数"))
                .accessibilityValue(String(localized: "\(points.reduce(0) { $0 + $1.reps }) 次")).accessibilityIdentifier("trend-total-reps")
            RecordOverviewMetric(title: String(localized: "最高重量"), value: (points.map(\.weight).max() ?? 0).formatted(), unit: String(localized: "公斤"))
                .accessibilityElement(children: .ignore).accessibilityLabel(String(localized: "最高重量"))
                .accessibilityValue(String(localized: "\((points.map(\.weight).max() ?? 0).formatted()) 公斤")).accessibilityIdentifier("trend-best-weight")
        }
    }
    private func dailyValue(_ point: RecordTrendPoint) -> some View {
        Text("\(point.weight.formatted()) 公斤 · \(point.reps) 次").monospacedDigit().foregroundStyle(Studio.muted)
    }
}
