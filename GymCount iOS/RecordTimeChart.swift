import SwiftUI
import Charts

struct RecordTimeChart: View {
    let records: [PhoneTrainingSession]
    let filter: RecordFilter
    let openDay: (Date) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metric = RecordTimeMetric.elapsed
    @State private var selectedDate: Date?

    private var points: [RecordDurationDay] { RecordDurationDay.summarize(records, metric: metric) }
    private var selected: RecordDurationDay? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.id.timeIntervalSince(selectedDate)) < abs($1.id.timeIntervalSince(selectedDate)) }
    }
    private var measured: Int { points.reduce(0) { $0 + $1.measuredRecords } }
    private var covered: Int { selected?.measuredRecords ?? measured }
    private var totalRecords: Int { selected?.recordCount ?? records.count }
    private var scale: Double { (points.map(\.seconds).max() ?? 0) >= 120 ? 60 : 1 }
    private var unit: String { scale == 60 ? String(localized: "分钟") : String(localized: "秒") }
    private var domain: ClosedRange<Date> {
        let first = points.first?.id ?? Date(), last = points.last?.id ?? first
        let padding = max(86400, last.timeIntervalSince(first) * 0.04)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }
    private var axisDates: [Date] {
        guard points.count > 2, let first = points.first?.id, let last = points.last?.id else { return points.map(\.id) }
        return [first, first.addingTimeInterval(last.timeIntervalSince(first) / 2), last]
    }
    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "运动时间")).font(.caption).foregroundStyle(Studio.muted)
                    Text(measured == 0 ? "—" : time(selected?.seconds ?? points.reduce(0) { $0 + $1.seconds }))
                        .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Studio.ink)
                        .accessibilityIdentifier("record-time-value")
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Menu {
                    ForEach(RecordTimeMetric.allCases, id: \.self) { value in
                        Button(value.title) { metric = value; selectedDate = nil }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(metric.title).font(.caption)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("record-time-metric")
            }
            if let selected {
                Button { openDay(selected.id) } label: {
                    HStack(spacing: 4) {
                        Text(recordDate(selected.id))
                        Image(systemName: "chevron.right")
                    }.font(.caption).frame(minHeight: 44)
                }.accessibilityHint(String(localized: "查看当天记录"))
                    .accessibilityIdentifier("record-time-open-day")
            }
            if points.isEmpty {
                Label(String(localized: "暂无时长数据"), systemImage: "clock")
                    .font(.subheadline).foregroundStyle(Studio.muted)
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .accessibilityIdentifier("record-time-empty")
            } else {
                chart
                if covered < totalRecords {
                    Text(String(localized: "\(covered)/\(totalRecords) 条有时长"))
                        .font(.caption2).foregroundStyle(Studio.muted)
                        .accessibilityIdentifier("record-time-coverage")
                }
            }
        }.buttonStyle(RecordPressStyle()).foregroundStyle(Studio.ink)
            .onChange(of: filter) { _, _ in selectedDate = nil }
            .onChange(of: points) { _, _ in selectedDate = nil }
            .animation(RecordMotion.animation(reduced: reduceMotion), value: metric)
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(x: .value(String(localized: "日期"), point.id),
                    y: .value(String(localized: "时长"), point.seconds / scale), width: .fixed(12))
                .cornerRadius(3).foregroundStyle(Studio.accent)
                .opacity(selected == nil || selected?.id == point.id ? 1 : 0.4)
                .accessibilityLabel(recordDate(point.id)).accessibilityValue(time(point.seconds))
            if point.seconds == 0 {
                PointMark(x: .value(String(localized: "日期"), point.id), y: .value(String(localized: "时长"), 0))
                    .foregroundStyle(Studio.accent).symbolSize(16)
            }
            if selected?.id == point.id {
                RuleMark(x: .value(String(localized: "日期"), point.id))
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
                        Text(date, format: recordChartDateFormat(first: points.first?.id, last: points.last?.id))
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
        .font(.caption2).accessibilityLabel(String(localized: "每日运动时间"))
        .accessibilityIdentifier("record-time-chart")
    }
}
