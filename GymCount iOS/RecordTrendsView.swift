import SwiftUI

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
    private var breakdownTitle: String {
        switch grouping {
        case .automatic, .day: String(localized: "每日汇总")
        case .week: String(localized: "每周汇总")
        case .month: String(localized: "每月汇总")
        }
    }

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
                            RecordTrendChartSection(points: points, grouping: grouping, totalRecords: records.count, filter: filter,
                                metric: $metric, granularity: $granularity, collapsed: $collapsed, open: open)
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
                .onChange(of: filter) { _, _ in refreshInsights(); persistPreferences() }
                .onChange(of: metric) { _, _ in refreshSeries(); persistPreferences() }
                .onChange(of: granularity) { _, _ in refreshSeries(); persistPreferences() }
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
