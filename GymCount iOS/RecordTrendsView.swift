import SwiftUI
import Charts

struct RecordTrendsView: View {
    @EnvironmentObject private var store: PhoneWorkoutStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var openRange: (ExerciseType?, DateInterval) -> Void
    @AppStorage("records.trends") private var savedPreferences = Data()
    @AppStorage("records.time-chart") private var legacyTimePreferences = Data()
    @State private var filter = RecordFilter(period: .all)
    @State private var insights = RecordTrainingInsights(records: [], filter: RecordFilter(period: .all))
    @State private var points: [RecordTrendPoint] = []
    @State private var grouping = RecordChartGranularity.day
    @State private var metric = RecordTrendMetric.active
    @State private var granularity = RecordChartGranularity.automatic
    @State private var collapsed = false
    @State private var restoredPreferences = false
    @State private var selectedDate: Date?
    @State private var chartScrollDate = Date()
    @State private var showDates = false
    @State private var showBreakdown = false
    @State private var supportingSpacing = SupportingSpacing()
    private struct SupportingSpacing: Equatable {
        var leadingWidth: CGFloat?
        var gap: CGFloat = Studio.wideInset
    }
    private var supportingColumns: [GridItem] {
        guard widthClass == .regular && typeSize < .xxLarge else { return [GridItem(.flexible())] }
        return [GridItem(supportingSpacing.leadingWidth.map { .fixed($0) } ?? .flexible(), spacing: supportingSpacing.gap, alignment: .top),
                GridItem(.flexible(), alignment: .top)]
    }

    private var records: [PhoneTrainingSession] { insights.filteredRecords }
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
    private var recordCount: Int { selected?.recordCount ?? records.count }
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
        let height: CGFloat = points.count <= 1 ? 104 : points.count <= 4 ? 132 : 156
        return max(height, widthClass == .regular ? 190 : height) + (typeSize.isAccessibilitySize ? 44 : 0)
    }
    private var breakdownTitle: String {
        switch grouping {
        case .automatic, .day: String(localized: "每日汇总")
        case .week: String(localized: "每周汇总")
        case .month: String(localized: "每月汇总")
        }
    }
    private func position(_ range: DateInterval) -> Date { range.start.addingTimeInterval(range.duration / 2) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: Studio.spacing) {
                        if records.isEmpty {
                            ContentUnavailableView(String(localized: "暂无记录"), systemImage: "chart.xyaxis.line")
                                .frame(maxWidth: .infinity).accessibilityIdentifier("trend-empty")
                        } else {
                            RecordTrainingOverview(insights: insights)
                            sectionDivider
                            VStack(alignment: .leading, spacing: 8) {
                                summary
                                if !collapsed {
                                    if plotted.isEmpty {
                                        RecordInlineState(title: String(localized: "暂无时长数据"), systemImage: "clock")
                                            .accessibilityIdentifier("trend-empty")
                                    } else { chart }
                                }
                                sectionDivider
                            }
                            LazyVGrid(columns: supportingColumns, alignment: .leading,
                                      spacing: widthClass == .regular ? Studio.wideInset : Studio.spacing) {
                                VStack(alignment: .leading, spacing: Studio.spacing) {
                                    RecordTrainingHeatmap(insights: insights, filter: filter) { range in open(range) }
                                    sectionDivider
                                }
                                VStack(alignment: .leading, spacing: Studio.spacing) {
                                    RecordExerciseDistribution(insights: insights) { filter.exercise = $0 }
                                    sectionDivider
                                    RecordWeightDistribution(insights: insights)
                                    sectionDivider
                                }
                            }
                            .onGeometryChange(for: SupportingSpacing.self) { geometry in
                                var spacing = SupportingSpacing()
                                if #available(iOS 27.1, *), let fold = geometry.reservedRegions(kind: .division).first(where: { $0.frame.height > $0.frame.width }) {
                                    spacing.gap = max(Studio.wideInset, fold.frame.width + fold.margins.leading + fold.margins.trailing)
                                    let leading = fold.frame.midX - spacing.gap / 2
                                    if leading >= 240 && geometry.size.width - leading - spacing.gap >= 240 {
                                        spacing.leadingWidth = leading
                                    } else { spacing = SupportingSpacing() }
                                }
                                return spacing
                            } action: { supportingSpacing = $0 }
                            VStack(alignment: .leading, spacing: 0) {
                                Button {
                                    withAnimation(RecordMotion.animation(reduced: reduceMotion)) { showBreakdown.toggle() }
                                } label: {
                                    HStack {
                                        Text(breakdownTitle).font(Studio.Fonts.section)
                                        Spacer(minLength: 8)
                                        Image(systemName: showBreakdown ? "chevron.up" : "chevron.down").font(Studio.Fonts.caption.weight(.semibold))
                                    }.foregroundStyle(Studio.muted).frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
                                }.buttonStyle(RecordPressStyle()).accessibilityIdentifier("trend-breakdown-disclosure")
                                if showBreakdown {
                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 12) { streaks }
                                        VStack(alignment: .leading, spacing: 4) { streaks }
                                    }.font(Studio.Fonts.caption).foregroundStyle(Studio.muted).padding(.vertical, 8)
                                    LazyVStack(spacing: 0) { ForEach(points.reversed()) { point in breakdown(point) } }
                                }
                            }
                        }
                    }.padding(.horizontal, Studio.inset).padding(.top, 8).padding(.bottom, 20)
                }.accessibilityIdentifier("trends-scroll")
            }.recordCanvasSpacing().background(Studio.background)
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { restorePreferences(); refreshInsights() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { refreshInsights() } }
                .onChange(of: store.historyRevision) { _, _ in refreshInsights() }
                .onChange(of: filter) { _, _ in selectedDate = nil; refreshInsights(); persistPreferences() }
                .onChange(of: points) { _, _ in selectedDate = nil }
                .onChange(of: metric) { _, _ in selectedDate = nil; refreshSeries(); persistPreferences() }
                .onChange(of: granularity) { _, _ in selectedDate = nil; refreshSeries(); persistPreferences() }
                .onChange(of: collapsed) { _, _ in persistPreferences() }
                .sheet(isPresented: $showDates) {
                    RecordDateSheet(singleDay: false, apply: { a, b in filter.start = a; filter.end = b; filter.period = .custom }, start: filter.start, end: filter.end)
                }
        }
    }

    private var sectionDivider: some View { Rectangle().fill(Studio.line).frame(height: Studio.hairline) }
    @ViewBuilder private var streaks: some View {
        Text(String(localized: "最长连续 \(insights.longestStreak) 天"))
        Text(String(localized: "当前连续 \(insights.currentStreak) 天"))
    }
    private func refreshInsights() {
        insights = RecordTrainingInsights(records: store.history, filter: filter)
        refreshSeries()
    }

    // Aggregate once per input change, never while building individual marks,
    // selecting a point, or receiving chart scroll-position updates.
    private func refreshSeries() {
        grouping = granularity.resolved(for: records.map(\.startTime))
        points = RecordTrendPoint.summarize(records, metric: metric, granularity: grouping, filter: filter)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordPageHeader(title: String(localized: "趋势"), identifier: "trend-heading") { filters }
            if filter.period == .custom {
                Text(filter.rangeTitle).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, Studio.inset).padding(.bottom, 8)
                    .accessibilityIdentifier("trend-custom-range")
            }
        }.background(Studio.background)
            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: Studio.hairline) }
            // Menu selection changes label width and can insert an exercise
            // icon. Keep the header anchored while updating the filtered data.
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { filterMenus }
            VStack(alignment: .trailing, spacing: 0) { filterMenus }
        }.buttonStyle(RecordPressStyle())
    }

    @ViewBuilder private var filterMenus: some View {
        Menu {
            Picker(String(localized: "动作"), selection: $filter.exercise) {
                Text(String(localized: "全部动作")).tag(ExerciseType?.none)
                ForEach(ExerciseType.allCases, id: \.self) { Label($0.recordName, image: $0.icon).tag(Optional($0)) }
            }
        } label: { filterLabel(filter.exercise?.recordName ?? String(localized: "全部动作"), exercise: filter.exercise) }
            .accessibilityIdentifier("trend-exercise-filter")
        Menu {
            ForEach([RecordFilter.Period.month, .quarter, .all], id: \.self) { period in Button(period.title) { filter.period = period } }
            Button(String(localized: "自定义日期")) { showDates = true }
        } label: { filterLabel(filter.period.title) }
            .accessibilityIdentifier("trend-period-filter")
    }

    private func filterLabel(_ title: String, exercise: ExerciseType? = nil) -> some View {
        RecordFilterLabel(title: title, exercise: exercise).fixedSize(horizontal: true, vertical: true)
    }

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

    private func breakdown(_ point: RecordTrendPoint) -> some View {
        Button { open(point.range) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(recordChartRangeTitle(point.range, granularity: grouping))
                    Spacer(minLength: 8)
                    Text(metric.formatted(point.value)).monospacedDigit().foregroundStyle(Studio.muted)
                    Image(systemName: "chevron.right").font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(recordChartRangeTitle(point.range, granularity: grouping))
                    Text(metric.formatted(point.value)).monospacedDigit().foregroundStyle(Studio.muted)
                }
            }.font(Studio.Fonts.body).frame(minHeight: 52).padding(.vertical, 4).contentShape(Rectangle()).foregroundStyle(Studio.ink)
        }.buttonStyle(RecordPressStyle()).accessibilityIdentifier("trend-breakdown-\(point.id.timeIntervalSince1970)")
            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: Studio.hairline) }
    }

    private func open(_ range: DateInterval) {
        guard let intersection = filter.intersection(with: range) else { return }
        openRange(filter.exercise, intersection)
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
        let visibleMaximum = plotted.filter { $0.range.start < visibleDomain.upperBound && $0.range.end > visibleDomain.lowerBound }
            .compactMap(\.value).max() ?? 0
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
            .chartYScale(domain: 0...max(metric.timeMetric == nil ? 1 : 2 / scale, visibleMaximum / scale * 1.1))
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

    private var preferences: RecordViewPreferences {
        RecordViewPreferences(filter: filter, metric: metric.rawValue, granularity: granularity.rawValue, collapsed: collapsed)
    }
    private func restorePreferences() {
        guard !restoredPreferences else { return }
        // A fresh trends visit starts with the complete training picture. Keep
        // chart presentation preferences, while exercise/date selection stays
        // within this visit instead of reopening a forgotten narrow filter.
        var fallback = preferences
        if savedPreferences.isEmpty, !legacyTimePreferences.isEmpty {
            let legacy = RecordViewPreferences.decode(legacyTimePreferences, fallback: fallback)
            fallback.metric = RecordTimeMetric(rawValue: legacy.metric)?.rawValue ?? fallback.metric
            fallback.granularity = legacy.granularity
            fallback.collapsed = legacy.collapsed
        }
        let saved = RecordViewPreferences.decode(savedPreferences, fallback: fallback)
        filter = RecordFilter(period: .all)
        metric = RecordTrendMetric(rawValue: saved.metric) ?? .active
        granularity = RecordChartGranularity(rawValue: saved.granularity) ?? .automatic
        collapsed = saved.collapsed
        restoredPreferences = true
        persistPreferences()
    }
    private func persistPreferences() {
        guard restoredPreferences else { return }
        savedPreferences = preferences.data
    }
}
