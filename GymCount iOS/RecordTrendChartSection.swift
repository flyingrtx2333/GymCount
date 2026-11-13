import SwiftUI
import Charts

// Keep per-frame chart scrolling/selection local; the calendar and distributions
// only receive new inputs when their records or filters actually change.
struct RecordTrendChartSection: View {
    let points: [RecordTrendPoint]
    let grouping: RecordChartGranularity
    let totalRecords: Int
    let filter: RecordFilter
    @Binding var metric: RecordTrendMetric
    @Binding var granularity: RecordChartGranularity
    @Binding var collapsed: Bool
    var open: (DateInterval) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDate: Date?
    @State private var chartScrollDate = Date()

    private var plotted: [RecordTrendPoint] { points.filter { $0.value != nil } }
    private var selected: RecordTrendPoint? {
        guard let selectedDate else { return nil }
        return plotted.first { selectedDate >= $0.range.start && selectedDate < $0.range.end }
            ?? plotted.min { abs(position($0.range).timeIntervalSince(selectedDate)) < abs(position($1.range).timeIntervalSince(selectedDate)) }
    }
    private var totalValue: Double? {
        let values = points.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return metric == .weight ? values.max() : values.reduce(0, +)
    }
    private var measured: Int { selected?.measuredRecords ?? points.reduce(0) { $0 + $1.measuredRecords } }
    private var recordCount: Int { selected?.recordCount ?? totalRecords }
    private var scale: Double { metric.timeMetric != nil && (plotted.compactMap(\.value).max() ?? 0) >= 120 ? 60 : 1 }
    private var unit: String {
        switch metric {
        case .active: scale == 60 ? String(localized: "分钟") : String(localized: "秒")
        case .reps: String(localized: "次数")
        case .weight: String(localized: "公斤")
        }
    }
    private var domain: ClosedRange<Date> {
        let first = points.first?.range.start ?? Date(), last = points.last?.range.end ?? first.addingTimeInterval(86400)
        return first...last
    }
    private var visibleLength: TimeInterval {
        let slots = grouping == .day ? 30 : 12
        let end = Calendar.current.date(byAdding: grouping.component, value: slots, to: domain.lowerBound) ?? domain.upperBound
        return min(domain.upperBound.timeIntervalSince(domain.lowerBound), end.timeIntervalSince(domain.lowerBound))
    }
    private var visibleDomain: ClosedRange<Date> {
        let first = min(max(domain.lowerBound, chartScrollDate), domain.upperBound.addingTimeInterval(-visibleLength))
        return first...first.addingTimeInterval(visibleLength)
    }
    private var axisDates: [Date] {
        let first = visibleDomain.lowerBound, last = visibleDomain.upperBound.addingTimeInterval(-1)
        let dates = typeSize.isAccessibilitySize ? [last] : typeSize >= .xxLarge ? [first, last]
            : [first, first.addingTimeInterval(last.timeIntervalSince(first) / 2), last]
        return Array(Set(dates.map { position(grouping.interval(containing: $0)) }))
            .filter { visibleDomain.contains($0) }.sorted()
    }
    private var chartHeight: CGFloat {
        (widthClass == .regular ? 190 : 156) + (typeSize.isAccessibilitySize ? 44 : 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            if !collapsed {
                if plotted.isEmpty {
                    RecordInlineState(title: String(localized: "暂无时长数据"), systemImage: "clock")
                        .accessibilityIdentifier("trend-empty")
                } else { chart }
            }
            Rectangle().fill(Studio.line).frame(height: Studio.hairline)
        }.onChange(of: points) { _, _ in selectedDate = nil }
            .onChange(of: metric) { _, _ in selectedDate = nil }
            .onChange(of: filter) { _, _ in selectedDate = nil }
    }
    private func position(_ range: DateInterval) -> Date { range.start.addingTimeInterval(range.duration / 2) }

    private var metricMenu: some View {
        Menu {
            ForEach(RecordTrendMetric.allCases, id: \.self) { value in
                Button { metric = value } label: {
                    if metric == value { Label(value.title, systemImage: "checkmark") }
                    else { Text(value.title) }
                }.accessibilityIdentifier("trend-metric-\(value.rawValue)")
            }
            Section(String(localized: "汇总方式")) {
                ForEach(RecordChartGranularity.allCases, id: \.self) { value in
                    Button { granularity = value } label: {
                        if granularity == value { Label(value.title, systemImage: "checkmark") }
                        else { Text(value.title) }
                    }.accessibilityIdentifier("trend-granularity-\(value.rawValue)")
                }
            }
            Divider()
            Button(collapsed ? String(localized: "展开图表") : String(localized: "收起图表"), action: toggleChart)
                .accessibilityIdentifier("trend-toggle-chart")
        } label: {
            HStack(spacing: 6) {
                Text(metric.compactTitle).font(Studio.Fonts.body.weight(.medium)).foregroundStyle(Studio.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Studio.accent)
            }.frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
        }.buttonStyle(RecordPressStyle()).foregroundStyle(Studio.ink)
            .accessibilityLabel(metric.title)
            .accessibilityValue(grouping.title).accessibilityIdentifier("trend-metric")
    }

    private var summaryValue: some View {
        RecordNumberText(value: metric.compactFormatted(selected?.value ?? totalValue), numberFont: Studio.Fonts.metric, unitFont: Studio.Fonts.caption)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore).accessibilityLabel(metric.title)
            .accessibilityValue(metric.formatted(selected?.value ?? totalValue)).accessibilityIdentifier("trend-summary-value")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    metricMenu.fixedSize()
                    Spacer(minLength: 12)
                    if selected != nil || metric == .active || metric == .weight { summaryValue.fixedSize() }
                    chartDisclosure
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { metricMenu; Spacer(minLength: 8); chartDisclosure }
                    if selected != nil || metric == .active || metric == .weight { summaryValue }
                }
            }
            if let selected {
                HStack(spacing: 4) {
                    Button { open(selected.range) } label: {
                        HStack(spacing: 6) {
                            Text(recordChartRangeTitle(selected.range, granularity: grouping))
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right").font(Studio.Fonts.caption)
                        }.frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
                    }.accessibilityHint(String(localized: "查看此范围记录")).accessibilityIdentifier("trend-open-day")
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(RecordMotion.animation(reduced: reduceMotion)) { selectedDate = nil }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: Studio.controlHeight, height: Studio.controlHeight)
                    }.accessibilityLabel(String(localized: "清除选择")).accessibilityIdentifier("trend-clear-selection")
                }.buttonStyle(RecordPressStyle()).font(Studio.Fonts.caption).foregroundStyle(Studio.accent)
            }
            if metric.timeMetric != nil && measured > 0 && measured < recordCount {
                Text(String(localized: "\(measured)/\(recordCount) 条有时长"))
                    .font(Studio.Fonts.axis).foregroundStyle(Studio.muted).accessibilityIdentifier("trend-time-coverage")
            }
        }
    }

    private var chartDisclosure: some View {
        Button(action: toggleChart) {
            Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                .font(.system(size: 13, weight: .semibold)).frame(width: Studio.controlHeight, height: Studio.controlHeight)
        }.buttonStyle(RecordPressStyle())
            .accessibilityLabel(collapsed ? String(localized: "展开图表") : String(localized: "收起图表"))
            .accessibilityIdentifier("trend-chart-disclosure")
    }

    private func toggleChart() {
        withAnimation(RecordMotion.animation(reduced: reduceMotion)) { collapsed.toggle(); selectedDate = nil }
    }
    private var chart: some View {
        let plotted = self.plotted
        let selectedID = selected?.id
        let scale = self.scale
        let unit = self.unit
        let axisDates = self.axisDates
        let visibleDomain = self.visibleDomain
        let maximum = plotted.compactMap(\.value).max() ?? 0
        return Chart(plotted) { point in
            let value = (point.value ?? 0) / scale
            if metric == .weight {
                LineMark(x: .value(String(localized: "日期"), position(point.range)), y: .value(unit, value))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value(String(localized: "日期"), position(point.range)), y: .value(unit, value))
                    .symbolSize(selectedID == point.id ? 65 : 22)
                    .accessibilityLabel(recordChartRangeTitle(point.range, granularity: grouping))
                    .accessibilityValue(metric.formatted(point.value))
            } else {
                BarMark(x: .value(String(localized: "日期"), position(point.range), unit: grouping.component), y: .value(unit, value), width: points.count <= 1 ? .fixed(14) : .ratio(0.7))
                    .cornerRadius(3).opacity(selectedID == nil || selectedID == point.id ? 1 : 0.4)
                    .accessibilityLabel(recordChartRangeTitle(point.range, granularity: grouping))
                    .accessibilityValue(metric.formatted(point.value))
                if value == 0 {
                    PointMark(x: .value(String(localized: "日期"), position(point.range)), y: .value(unit, 0)).symbolSize(16)
                }
            }
            if selectedID == point.id {
                RuleMark(x: .value(String(localized: "日期"), position(point.range)))
                    .foregroundStyle(Studio.line).lineStyle(StrokeStyle(dash: [3, 4]))
            }
        }.foregroundStyle(Studio.accent)
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in
                    withAnimation(RecordMotion.animation(reduced: reduceMotion)) { proxy.selectXValue(at: event.location.x) }
                }
            }
            .chartXScale(domain: domain)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleLength)
            .chartScrollPosition(x: $chartScrollDate)
            .chartYScale(domain: 0...max(metric.timeMetric == nil ? 1 : 2 / scale, maximum / scale * 1.1))
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisValueLabel(anchor: axisDates.count == 1 ? (points.count == 1 ? .top : .topTrailing) : value.index == 0 ? .topLeading : value.index == axisDates.count - 1 ? .topTrailing : .top) {
                        if let date = value.as(Date.self) {
                            Text(grouping.interval(containing: date).start, format: recordChartAxisFormat(grouping, first: visibleDomain.lowerBound, last: visibleDomain.upperBound.addingTimeInterval(-1))).lineLimit(1)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: Studio.hairline)).foregroundStyle(Studio.line.opacity(0.65))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric.timeMetric == nil
                                 ? number.formatted(.number.precision(.fractionLength(0...1)))
                                 : RecordTrendMetric.clock(number * scale))
                        }
                    }
                }
            }
            .frame(height: chartHeight).font(Studio.Fonts.axis).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityLabel(metric.title).accessibilityIdentifier("trend-chart")
            .accessibilityValue(visibleDomain.lowerBound.formatted(date: .abbreviated, time: .omitted)
                + " – " + visibleDomain.upperBound.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))
            .onChange(of: domain, initial: true) { _, value in
                chartScrollDate = value.upperBound.addingTimeInterval(-visibleLength)
            }
            .animation(RecordMotion.animation(reduced: reduceMotion), value: metric)
            .animation(RecordMotion.animation(reduced: reduceMotion), value: selectedID)
    }

}
