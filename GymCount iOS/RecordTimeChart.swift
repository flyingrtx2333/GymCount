import SwiftUI
import Charts

func recordChartRangeTitle(_ range: DateInterval, granularity: RecordChartGranularity) -> String {
    if granularity == .day { return recordDate(range.start) }
    if granularity == .month { return range.start.formatted(.dateTime.year().month()) }
    let end = range.end.addingTimeInterval(-1)
    let calendar = Calendar.current
    let showYear = calendar.component(.year, from: range.start) != calendar.component(.year, from: end)
        || calendar.component(.year, from: range.start) != calendar.component(.year, from: Date())
    let format: Date.FormatStyle = showYear ? .dateTime.year().month().day() : .dateTime.month().day()
    return range.start.formatted(format) + " – " + end.formatted(format)
}

func recordChartAxisFormat(_ granularity: RecordChartGranularity, first: Date?, last: Date?) -> Date.FormatStyle {
    guard granularity == .month else { return recordChartDateFormat(first: first, last: last) }
    let year = first.map { Calendar.current.component(.year, from: $0) }
    let showYear = year != last.map { Calendar.current.component(.year, from: $0) } || year != Calendar.current.component(.year, from: Date())
    return showYear ? .dateTime.year(.twoDigits).month(.twoDigits) : .dateTime.month(.twoDigits)
}

struct RecordTimeChart: View {
    let records: [PhoneTrainingSession]
    let filter: RecordFilter
    let openRange: (DateInterval) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("records.time-chart") private var savedPreferences = Data()
    @State private var metric = RecordTimeMetric.elapsed
    @State private var granularity = RecordChartGranularity.automatic
    @State private var collapsed = false
    @State private var restoredPreferences = false
    @State private var selectedDate: Date?

    private var grouping: RecordChartGranularity { granularity.resolved(for: records.map(\.startTime)) }
    private var points: [RecordDurationDay] { RecordDurationDay.summarize(records, metric: metric, granularity: grouping) }
    private var selected: RecordDurationDay? {
        guard let selectedDate else { return nil }
        return points.first { selectedDate >= $0.range.start && selectedDate < $0.range.end }
            ?? points.min { abs(position($0.range).timeIntervalSince(selectedDate)) < abs(position($1.range).timeIntervalSince(selectedDate)) }
    }
    private var measured: Int { points.reduce(0) { $0 + $1.measuredRecords } }
    private var covered: Int { selected?.measuredRecords ?? measured }
    private var totalRecords: Int { selected?.recordCount ?? records.count }
    private var scale: Double { (points.map(\.seconds).max() ?? 0) >= 120 ? 60 : 1 }
    private var unit: String { scale == 60 ? String(localized: "分钟") : String(localized: "秒") }
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
    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "运动时间") + " · " + grouping.title).font(.caption).foregroundStyle(Studio.muted)
                    Text(measured == 0 ? "—" : time(selected?.seconds ?? points.reduce(0) { $0 + $1.seconds }))
                        .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Studio.ink)
                        .accessibilityIdentifier("record-time-value")
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Menu {
                    ForEach(RecordTimeMetric.allCases, id: \.self) { value in
                        Button(value.title) { metric = value; selectedDate = nil }
                    }
                    Section(String(localized: "汇总方式")) {
                        ForEach(RecordChartGranularity.allCases, id: \.self) { value in
                            Button { granularity = value } label: {
                                if granularity == value { Label(value.title, systemImage: "checkmark") }
                                else { Text(value.title) }
                            }.accessibilityIdentifier("record-time-granularity-\(value.rawValue)")
                        }
                    }
                    Divider()
                    Button(collapsed ? String(localized: "展开图表") : String(localized: "收起图表")) {
                        withAnimation(RecordMotion.animation(reduced: reduceMotion)) { collapsed.toggle(); selectedDate = nil }
                    }.accessibilityIdentifier("record-time-toggle-chart")
                } label: {
                    HStack(spacing: 5) {
                        Text(metric.title).font(.caption)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }.frame(minHeight: 44)
                }.accessibilityValue(grouping.title).accessibilityIdentifier("record-time-metric")
            }
            if !collapsed {
                if let selected {
                    Button { openRange(selected.range) } label: {
                        HStack(spacing: 4) {
                            Text(recordChartRangeTitle(selected.range, granularity: grouping))
                            Image(systemName: "chevron.right")
                        }.font(.caption).frame(minHeight: 44)
                    }.accessibilityHint(String(localized: "查看此范围记录"))
                        .accessibilityIdentifier("record-time-open-day")
                }
                if points.isEmpty {
                    Label(String(localized: "暂无时长数据"), systemImage: "clock")
                        .font(.subheadline).foregroundStyle(Studio.muted)
                        .frame(maxWidth: .infinity, minHeight: 90)
                        .accessibilityIdentifier("record-time-empty")
                } else {
                    chart
                }
            }
            if measured > 0 && covered < totalRecords {
                Text(String(localized: "\(covered)/\(totalRecords) 条有时长"))
                    .font(.caption2).foregroundStyle(Studio.muted)
                    .accessibilityIdentifier("record-time-coverage")
            }
        }.buttonStyle(RecordPressStyle()).foregroundStyle(Studio.ink)
            .onAppear {
                guard !restoredPreferences else { return }
                let saved = RecordViewPreferences.decode(savedPreferences, fallback: preferences)
                metric = RecordTimeMetric(rawValue: saved.metric) ?? .elapsed
                granularity = RecordChartGranularity(rawValue: saved.granularity) ?? .automatic
                collapsed = saved.collapsed
                restoredPreferences = true
            }
            .onChange(of: filter) { _, _ in selectedDate = nil; persistPreferences() }
            .onChange(of: points) { _, _ in selectedDate = nil }
            .onChange(of: metric) { _, _ in persistPreferences() }
            .onChange(of: granularity) { _, _ in selectedDate = nil; persistPreferences() }
            .onChange(of: collapsed) { _, _ in persistPreferences() }
            .animation(RecordMotion.animation(reduced: reduceMotion), value: metric)
    }

    private var preferences: RecordViewPreferences {
        RecordViewPreferences(filter: filter, metric: metric.rawValue, granularity: granularity.rawValue, collapsed: collapsed)
    }
    private func persistPreferences() {
        guard restoredPreferences else { return }
        savedPreferences = preferences.data
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(x: .value(String(localized: "日期"), position(point.range)),
                    y: .value(String(localized: "时长"), point.seconds / scale), width: .fixed(barWidth))
                .cornerRadius(3).foregroundStyle(Studio.accent)
                .opacity(selected == nil || selected?.id == point.id ? 1 : 0.4)
                .accessibilityLabel(recordChartRangeTitle(point.range, granularity: grouping)).accessibilityValue(time(point.seconds))
            if point.seconds == 0 {
                PointMark(x: .value(String(localized: "日期"), position(point.range)), y: .value(String(localized: "时长"), 0))
                    .foregroundStyle(Studio.accent).symbolSize(16)
            }
            if selected?.id == point.id {
                RuleMark(x: .value(String(localized: "日期"), position(point.range)))
                    .foregroundStyle(Studio.line).lineStyle(StrokeStyle(dash: [3, 4]))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...max(1, (points.map(\.seconds).max() ?? 0) / scale * 1.1))
        .chartYAxisLabel(unit, position: .topLeading)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisValueLabel(anchor: axisDates.count == 1 ? .top : value.index == 0 ? .topLeading : value.index == axisDates.count - 1 ? .topTrailing : .top) {
                    if let date = value.as(Date.self) {
                        Text(grouping.interval(containing: date).start, format: recordChartAxisFormat(grouping, first: points.first?.id, last: points.last?.id))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Studio.line)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number.formatted(.number.precision(.fractionLength(0...1))))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
                .simultaneously(with: DragGesture(minimumDistance: 20).onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    proxy.selectXValue(at: value.location.x)
                })
        }
        .frame(height: typeSize.isAccessibilitySize ? 260 : 150)
        .font(.caption2).accessibilityLabel(String(localized: "运动时间趋势"))
        .accessibilityIdentifier("record-time-chart")
    }
}
