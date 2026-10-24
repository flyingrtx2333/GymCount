import SwiftUI
import Charts

struct RecordTrendsView: View {
    @EnvironmentObject private var store: PhoneWorkoutStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var openRange: (ExerciseType, DateInterval) -> Void
    @AppStorage("records.trends") private var savedPreferences = Data()
    @State private var filter = RecordFilter(exercise: .benchPress, period: .month)
    @State private var showReps = false
    @State private var granularity = RecordChartGranularity.automatic
    @State private var collapsed = false
    @State private var restoredPreferences = false
    @State private var selectedDate: Date?
    @State private var showDates = false
    private var records: [PhoneTrainingSession] { store.history.filter(filter.includes) }
    private var grouping: RecordChartGranularity { granularity.resolved(for: records.map(\.startTime)) }
    private var points: [RecordTrendBucket] {
        RecordTrendBucket.summarize(records, granularity: grouping, reps: filter.reps, weight: filter.weight)
    }
    private var selected: RecordTrendBucket? {
        guard let selectedDate else { return points.last }
        return points.first { selectedDate >= $0.range.start && selectedDate < $0.range.end }
            ?? points.min { abs(position($0.range).timeIntervalSince(selectedDate)) < abs(position($1.range).timeIntervalSince(selectedDate)) }
    }
    private var domain: ClosedRange<Date> {
        let first = points.first?.range.start ?? Date(), last = points.last?.range.end ?? first.addingTimeInterval(86400)
        return first...last
    }
    private var axisDates: [Date] {
        guard let first = points.first?.id, let last = points.last?.id else { return [] }
        let middle = grouping.interval(containing: first.addingTimeInterval(last.timeIntervalSince(first) / 2)).start
        return Array(Set([first, middle, last])).sorted().map { position(grouping.interval(containing: $0)) }
    }
    private var barWidth: CGFloat {
        let slots = Calendar.current.dateComponents([grouping.component], from: domain.lowerBound, to: domain.upperBound).value(for: grouping.component) ?? points.count
        return CGFloat(max(1, min(18, 260 / Double(max(1, slots)) * 0.65)))
    }
    private func position(_ range: DateInterval) -> Date { range.start.addingTimeInterval(range.duration / 2) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack { Text(String(localized: "趋势")).font(.title2.weight(.semibold)); Spacer() }
                    .padding(.horizontal, 20).frame(minHeight: 56)
                if !typeSize.isAccessibilitySize { filters }
                ScrollView {
                    VStack(spacing: 0) {
                        if typeSize.isAccessibilitySize { filters }
                        VStack(alignment: .leading, spacing: 24) {
                            if points.isEmpty {
                                ContentUnavailableView(String(localized: "暂无记录"), systemImage: "chart.xyaxis.line")
                                    .frame(maxWidth: .infinity)
                            } else {
                                if let selected { selectedDay(selected) }
                                if !collapsed { chart }
                                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                                layout { metrics }
                                Text(grouping.recordsTitle).font(.headline)
                                LazyVStack(spacing: 0) {
                                    ForEach(points.reversed()) { point in
                                        Button { openRange(filter.exercise ?? .benchPress, point.range) } label: {
                                            ViewThatFits(in: .horizontal) {
                                                HStack { Text(recordChartRangeTitle(point.range, granularity: grouping)); Spacer(minLength: 8); dailyValue(point); Image(systemName: "chevron.right").font(.caption) }
                                                VStack(alignment: .leading, spacing: 4) { Text(recordChartRangeTitle(point.range, granularity: grouping)); dailyValue(point) }
                                            }.font(.subheadline).frame(minHeight: 56).contentShape(Rectangle()).foregroundStyle(Studio.ink)
                                        }.buttonStyle(RecordPressStyle())
                                            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: 0.5) }
                                    }
                                }
                            }
                        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
                    }
                }
            }.background(Studio.background)
                .toolbar(.hidden, for: .navigationBar, .tabBar)
                .animation(RecordMotion.animation(reduced: reduceMotion), value: filter)
                .onAppear {
                    guard !restoredPreferences else { return }
                    let saved = RecordViewPreferences.decode(savedPreferences, fallback: preferences)
                    filter = saved.filter
                    if filter.exercise == nil { filter.exercise = .benchPress }
                    showReps = saved.metric == "reps"
                    granularity = RecordChartGranularity(rawValue: saved.granularity) ?? .automatic
                    collapsed = saved.collapsed
                    restoredPreferences = true
                }
                .onChange(of: filter) { _, _ in selectedDate = nil; persistPreferences() }
                .onChange(of: showReps) { _, _ in persistPreferences() }
                .onChange(of: granularity) { _, _ in selectedDate = nil; persistPreferences() }
                .onChange(of: collapsed) { _, _ in persistPreferences() }
                .sheet(isPresented: $showDates) {
                    RecordDateSheet(singleDay: false, apply: { a, b in filter.start = a; filter.end = b; filter.period = .custom }, start: filter.start, end: filter.end)
                }
        }
    }
    private var filters: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return VStack(alignment: .leading, spacing: 0) {
            if filter.period == .custom {
                Text(filter.rangeTitle).font(.caption).foregroundStyle(Studio.muted)
                    .padding(.horizontal, 20).padding(.top, 6)
                    .accessibilityIdentifier("trend-custom-range")
            }
            layout {
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
                    Section(String(localized: "汇总方式")) {
                        ForEach(RecordChartGranularity.allCases, id: \.self) { value in
                            Button { granularity = value } label: {
                                if granularity == value { Label(value.title, systemImage: "checkmark") }
                                else { Text(value.title) }
                            }.accessibilityIdentifier("trend-granularity-\(value.rawValue)")
                        }
                    }
                    Divider()
                    Button(collapsed ? String(localized: "展开图表") : String(localized: "收起图表")) {
                        withAnimation(RecordMotion.animation(reduced: reduceMotion)) { collapsed.toggle(); selectedDate = nil }
                    }.accessibilityIdentifier("trend-toggle-chart")
                } label: { RecordFilterLabel(title: showReps ? String(localized: "次数") : String(localized: "最大重量")).frame(maxWidth: .infinity) }
                    .accessibilityValue(grouping.title).accessibilityIdentifier("trend-metric")
            }.padding(.horizontal, 12)
        }.buttonStyle(RecordPressStyle()).padding(.vertical, 5).background(Studio.background)
            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: 0.5) }
    }
    private func selectedDay(_ point: RecordTrendBucket) -> some View {
        Button { openRange(filter.exercise ?? .benchPress, point.range) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(showReps ? String(localized: "\(point.reps) 次") : String(localized: "\(point.weight.formatted()) 公斤"))
                        .font(.title.weight(.semibold)).monospacedDigit().contentTransition(.numericText()).foregroundStyle(Studio.ink)
                    Text(recordChartRangeTitle(point.range, granularity: grouping)).font(.caption).foregroundStyle(Studio.muted)
                }
                Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(Studio.accent).accessibilityHidden(true)
                Spacer(minLength: 0)
            }.frame(minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(RecordPressStyle()).accessibilityHint(String(localized: "查看此范围记录")).accessibilityIdentifier("trend-open-day")
    }
    private var chart: some View {
        Chart(points) { point in
            if showReps {
                BarMark(x: .value(String(localized: "日期"), position(point.range)), y: .value(String(localized: "次数"), point.reps), width: .fixed(barWidth))
                    .cornerRadius(3).opacity(selected?.id == point.id ? 1 : 0.55)
            } else {
                LineMark(x: .value(String(localized: "日期"), position(point.range)), y: .value(String(localized: "公斤"), point.weight))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value(String(localized: "日期"), position(point.range)), y: .value(String(localized: "公斤"), point.weight))
                    .symbolSize(selected?.id == point.id ? 65 : 22)
            }
            if selected?.id == point.id {
                RuleMark(x: .value(String(localized: "日期"), position(point.range)))
                    .foregroundStyle(Studio.line).lineStyle(StrokeStyle(dash: [3, 4]))
            }
        }.foregroundStyle(Studio.accent)
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in
                    withAnimation(RecordMotion.animation(reduced: reduceMotion)) { proxy.selectXValue(at: event.location.x) }
                }.simultaneously(with: DragGesture(minimumDistance: 20).onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    proxy.selectXValue(at: value.location.x)
                })
            }
            .chartXScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisValueLabel(anchor: axisDates.count == 1 ? .top : value.index == 0 ? .topLeading : value.index == axisDates.count - 1 ? .topTrailing : .top) {
                        if let date = value.as(Date.self) {
                            Text(grouping.interval(containing: date).start, format: recordChartAxisFormat(grouping, first: points.first?.id, last: points.last?.id)).fixedSize()
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
            .accessibilityLabel(showReps ? String(localized: "次数趋势") : String(localized: "最高重量趋势")).accessibilityIdentifier("trend-chart")
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
    private var preferences: RecordViewPreferences {
        RecordViewPreferences(filter: filter, metric: showReps ? "reps" : "weight", granularity: granularity.rawValue, collapsed: collapsed)
    }
    private func persistPreferences() {
        guard restoredPreferences else { return }
        savedPreferences = preferences.data
    }
    private func dailyValue(_ point: RecordTrendBucket) -> some View {
        Text("\(point.weight.formatted()) 公斤 · \(point.reps) 次").monospacedDigit().foregroundStyle(Studio.muted)
    }
}
