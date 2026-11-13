import SwiftUI

// A single drawing surface keeps the small contribution cells from creating
// overlapping touch targets. Date selection also has a native calendar and VO.
struct RecordTrainingHeatmap: View {
    private let days: [RecordTrainingInsights.TrainingDay]
    let filter: RecordFilter
    var openDay: (DateInterval) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDate: Date?
    @State private var scrollTarget: Date?
    @State private var selectedYear: Int?
    @State private var showCalendar = false
    @State private var contentOriginX: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @Namespace private var viewportSpace

    init(records: [PhoneTrainingSession], filter: RecordFilter, openDay: @escaping (DateInterval) -> Void) {
        self.init(insights: RecordTrainingInsights(records: records, filter: filter), filter: filter, openDay: openDay)
    }

    init(insights: RecordTrainingInsights, filter: RecordFilter, openDay: @escaping (DateInterval) -> Void) {
        days = insights.days
        self.filter = filter
        self.openDay = openDay
    }

    private let calendar = Calendar.current
    private var cellSide: CGFloat { typeSize >= .xxLarge ? 18 : 14 }
    private let cellGap: CGFloat = 4
    private let monthHeight: CGFloat = 22
    private var pitch: CGFloat { cellSide + cellGap }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var lastDay: Date {
        if filter.period == .all, let selectedYear,
           let start = calendar.date(from: DateComponents(year: selectedYear + 1, month: 1, day: 1)),
           let end = calendar.date(byAdding: .day, value: -1, to: start) { return min(end, today) }
        return filter.period == .custom ? min(calendar.startOfDay(for: filter.end), today) : today
    }
    private var firstDay: Date {
        if filter.period == .all, let selectedYear {
            return calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) ?? lastDay
        }
        if filter.period == .custom { return min(calendar.startOfDay(for: filter.start), lastDay) }
        let count: Int = switch filter.period {
        case .week: 6
        case .month: 29
        case .quarter: 89
        case .all: 363
        case .custom: 0
        }
        return calendar.date(byAdding: .day, value: -count, to: lastDay) ?? lastDay
    }
    private var firstMonday: Date {
        let offset = (calendar.component(.weekday, from: firstDay) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: firstDay) ?? firstDay
    }
    private var weekCount: Int {
        let count = calendar.dateComponents([.day], from: firstMonday, to: lastDay).day ?? 0
        return max(1, count / 7 + 1)
    }
    private var selection: Date {
        if let selectedDate, selectedDate >= firstDay, selectedDate <= lastDay { return selectedDate }
        return days.last(where: { $0.date >= firstDay && $0.date <= lastDay })?.date ?? lastDay
    }
    private var selected: RecordTrainingInsights.TrainingDay? { days.first { calendar.isDate($0.date, inSameDayAs: selection) } }
    private var years: [Int] {
        let current = calendar.component(.year, from: today)
        let first = days.first.map { calendar.component(.year, from: $0.date) } ?? current
        return Array((min(first, current)...current).reversed())
    }
    private var rangeIdentity: String { "\(firstDay.timeIntervalSinceReferenceDate)-\(lastDay.timeIntervalSinceReferenceDate)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            HStack(alignment: .top, spacing: 6) {
                weekdayLabels.accessibilityHidden(true)
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        grid
                            .frame(width: CGFloat(weekCount) * pitch - cellGap,
                                   height: monthHeight + 7 * pitch - cellGap)
                            .background {
                                GeometryReader { geometry in
                                    let origin = geometry.frame(in: .named(viewportSpace)).minX
                                    Color.clear
                                        .onAppear { contentOriginX = origin }
                                        .onChange(of: origin) { _, value in contentOriginX = value }
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                HStack(spacing: 0) {
                                    ForEach(0..<weekCount, id: \.self) { week in
                                        Color.clear.frame(width: pitch, height: 1).id(week)
                                    }
                                }.allowsHitTesting(false).accessibilityHidden(true)
                            }
                    }.scrollIndicators(.hidden).defaultScrollAnchor(.trailing)
                        .background {
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear { viewportWidth = geometry.size.width }
                                    .onChange(of: geometry.size.width) { _, value in viewportWidth = value }
                            }
                        }
                        .onChange(of: scrollTarget) { _, date in
                            guard let date else { return }
                            let offset = calendar.dateComponents([.day], from: firstMonday, to: date).day ?? 0
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                                scroll.scrollTo(offset / 7, anchor: .center)
                            }
                        }
                }.coordinateSpace(name: viewportSpace).id(rangeIdentity)
            }
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2).fill(color(for: level))
                        .frame(width: 10, height: 10).accessibilityHidden(true)
                }
            }.font(Studio.Fonts.axis).foregroundStyle(Studio.muted).accessibilityHidden(true)
            if selectedDate != nil { selectionRow }
        }.foregroundStyle(Studio.ink)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trend-training-calendar")
            .onChange(of: filter) { _, _ in selectedYear = nil; selectedDate = nil; scrollTarget = nil }
            .sheet(isPresented: $showCalendar) { calendarSheet }
    }

    private var yearRangeTitle: String {
        let first = calendar.component(.year, from: firstDay)
        let last = calendar.component(.year, from: lastDay)
        return first == last ? first.formatted(.number.grouping(.never))
            : "\(first.formatted(.number.grouping(.never)))–\(last.formatted(.number.grouping(.never)))"
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(String(localized: "日历")).font(Studio.Fonts.section)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 4) {
                if filter.period == .all {
                    Menu {
                        Button(String(localized: "近一年")) { changeYear(nil) }
                        ForEach(years, id: \.self) { year in
                            Button(year.formatted(.number.grouping(.never))) { changeYear(year) }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(selectedYear.map { $0.formatted(.number.grouping(.never)) } ?? String(localized: "近一年"))
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }.font(Studio.Fonts.caption).foregroundStyle(Studio.muted).frame(minHeight: Studio.controlHeight)
                    }.buttonStyle(RecordPressStyle()).accessibilityIdentifier("trend-heatmap-range")
                } else {
                    Text(yearRangeTitle).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                dateButton
            }
        }
    }

    private var weekdayLabels: some View {
        VStack(spacing: cellGap) {
            ForEach(0..<7) { row in
                Text([0, 2, 4].contains(row) ? calendar.veryShortStandaloneWeekdaySymbols[(row + 1) % 7] : "")
                    .font(Studio.Fonts.axis).foregroundStyle(Studio.muted)
                    .frame(width: 14, height: cellSide)
            }
        }.padding(.top, monthHeight).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var grid: some View {
        let first = firstDay, last = lastDay, monday = firstMonday, columns = weekCount
        let pitch = self.pitch, side = cellSide
        let highlightedDay = selectedDate == nil ? nil : selection
        let lookup = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        let maximum = max(1, days.filter { $0.date >= first && $0.date <= last }.map(\.recordCount).max() ?? 1)
        let visibleRange = max(0, -contentOriginX)..<(max(0, -contentOriginX) + viewportWidth)
        let firstColumn = max(0, min(columns, Int(floor(visibleRange.lowerBound / pitch))))
        let lastColumn = viewportWidth > 0 ? max(firstColumn, min(columns, Int(ceil(visibleRange.upperBound / pitch)))) : columns
        let colors = (0...4).map { color(for: $0) }
        return Canvas { context, _ in
            drawMonths(in: &context, visibleRange: visibleRange, first: first, last: last, monday: monday, columns: columns, pitch: pitch)
            for column in firstColumn..<lastColumn {
                for row in 0..<7 {
                    guard let day = calendar.date(byAdding: .day, value: column * 7 + row, to: monday),
                          day >= first, day <= last else { continue }
                    let count = lookup[day]?.recordCount ?? 0
                    let level = count == 0 ? 0 : max(1, min(4, Int(ceil(Double(count) / Double(maximum) * 4))))
                    let rect = CGRect(x: CGFloat(column) * pitch, y: monthHeight + CGFloat(row) * pitch,
                                      width: side, height: side)
                    let shape = Path(roundedRect: rect, cornerRadius: 3)
                    context.fill(shape, with: .color(colors[level]))
                    if day == highlightedDay {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 2),
                                       with: .color(Studio.ink), lineWidth: 1.5)
                    }
                }
            }
        }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { event in
                let column = Int(floor(event.location.x / pitch))
                let y = event.location.y - monthHeight
                guard y >= 0, event.location.x >= 0, column < weekCount,
                      event.location.x.truncatingRemainder(dividingBy: pitch) <= cellSide,
                      y.truncatingRemainder(dividingBy: pitch) <= cellSide else { return }
                let row = Int(floor(y / pitch))
                guard row < 7,
                      let date = calendar.date(byAdding: .day, value: column * 7 + row, to: firstMonday),
                      date >= firstDay, date <= lastDay else { return }
                choose(date)
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "训练日历"))
            .accessibilityValue(selectionDescription)
            .accessibilityHint(String(localized: "上下轻扫选择日期"))
            .accessibilityAdjustableAction { direction in
                let offset = direction == .increment ? 1 : direction == .decrement ? -1 : 0
                guard let next = calendar.date(byAdding: .day, value: offset, to: selection),
                      next >= firstDay, next <= lastDay else { return }
                choose(next, reveal: true)
            }
            .accessibilityActions {
                if selected != nil { Button(String(localized: "查看当天记录"), action: openSelection) }
            }
            .accessibilityIdentifier("trend-training-heatmap")
    }

    private func drawMonths(in context: inout GraphicsContext, visibleRange: Range<CGFloat>,
                            first: Date, last: Date, monday: Date, columns: Int, pitch: CGFloat) {
        guard !visibleRange.isEmpty else { return }
        let visibleStart = visibleRange.lowerBound
        let visibleEnd = visibleRange.upperBound
        var nextLabelX: CGFloat = 0
        var previousMonth: Int?
        for column in 0..<columns {
            guard let week = calendar.date(byAdding: .day, value: column * 7, to: monday) else { continue }
            let day = max(first, week)
            let month = calendar.component(.month, from: day)
            guard month != previousMonth else { continue }
            previousMonth = month
            let isFirst = column == 0
            let format: Date.FormatStyle = month == 1 || isFirst ? .dateTime.year().month(.abbreviated) : .dateTime.month(.abbreviated)
            let label = context.resolve(Text(day.formatted(format)).font(Studio.Fonts.axis).foregroundColor(Studio.muted))
            let size = label.measure(in: CGSize(width: .greatestFiniteMagnitude, height: monthHeight))
            let x = CGFloat(column) * pitch
            // Keep the cells scrollable edge-to-edge, but draw a month only
            // while its complete measured label is inside the viewport.
            guard x >= visibleStart, x + size.width <= visibleEnd else { continue }
            // First/January labels carry the year. Suppress a preceding label
            // if it would collide; do not squeeze December and January together.
            let januaryNext = calendar.date(byAdding: .month, value: 1, to: day).map { calendar.component(.month, from: $0) == 1 } ?? false
            let remaining = CGFloat(columns - column) * pitch
            guard x >= nextLabelX, size.width <= remaining else { continue }
            if januaryNext, let january = calendar.date(from: DateComponents(year: calendar.component(.year, from: day) + 1, month: 1, day: 1)), january <= last {
                let januaryColumn = CGFloat(calendar.dateComponents([.day], from: monday, to: january).day ?? 0) / 7
                if x + size.width + 12 > floor(januaryColumn) * pitch { continue }
            }
            context.draw(label, at: CGPoint(x: x, y: 0), anchor: .topLeading)
            nextLabelX = x + size.width + 12
        }
    }

    private var selectionRow: some View {
        Group {
            if typeSize.isAccessibilitySize {
                verticalSelection
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        selectedDateLabel.fixedSize()
                        Spacer(minLength: 0)
                        openDayButton.fixedSize()
                        clearSelection
                    }
                    verticalSelection
                }
            }
        }.buttonStyle(RecordPressStyle())
    }

    private var verticalSelection: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedDateLabel
            HStack { openDayButton; Spacer(minLength: 0); clearSelection }
        }
    }

    private var selectedDateLabel: some View {
        Text(calendar.component(.year, from: selection) == calendar.component(.year, from: today)
             ? selection.formatted(.dateTime.month().day())
             : selection.formatted(.dateTime.year().month().day()))
            .font(Studio.Fonts.caption).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
    }

    private var clearSelection: some View {
        Button { selectedDate = nil } label: {
            Image(systemName: "xmark").font(Studio.Fonts.caption).frame(width: Studio.controlHeight, height: Studio.controlHeight)
        }.foregroundStyle(Studio.muted).accessibilityLabel(String(localized: "清除选择"))
    }

    private var dateButton: some View {
        Button { selectedDate = selection; showCalendar = true } label: {
            Image(systemName: "calendar").frame(width: Studio.controlHeight, height: Studio.controlHeight).contentShape(Rectangle())
        }.font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
            .accessibilityLabel(String(localized: "选择日期"))
            .accessibilityValue(selection.formatted(date: .complete, time: .omitted))
            .accessibilityIdentifier("trend-heatmap-date")
    }

    private var openDayButton: some View {
        Button(action: openSelection) {
            HStack(spacing: 5) {
                (Text(String(localized: "\(selected?.recordCount ?? 0) 条"))
                 + Text(" · ") + Text(String(localized: "\(selected?.reps ?? 0) 次")))
                    .fixedSize(horizontal: false, vertical: true)
                if selected != nil { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)) }
            }.font(Studio.Fonts.caption).frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
        }.foregroundStyle(selected == nil ? Studio.muted : Studio.accent)
            .disabled(selected == nil)
            .accessibilityLabel(String(localized: "查看当天记录"))
            .accessibilityValue(selectionDescription)
            .accessibilityIdentifier("trend-heatmap-open-day")
    }

    private var calendarSheet: some View {
        NavigationStack {
            Form {
                if typeSize.isAccessibilitySize {
                    datePicker.datePickerStyle(.compact)
                } else {
                    datePicker.datePickerStyle(.graphical)
                }
            }.recordListStyle().navigationTitle(String(localized: "选择日期"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成")) { showCalendar = false }
                    }
                }.tint(Studio.accent)
        }.presentationDetents([.large])
    }

    private var datePicker: some View {
        DatePicker(String(localized: "日期"), selection: Binding(get: { selection }, set: { choose($0, reveal: true) }),
                   in: firstDay...lastDay, displayedComponents: .date)
    }

    private var selectionDescription: String {
        selection.formatted(date: .complete, time: .omitted) + ", "
            + String(localized: "\(selected?.recordCount ?? 0) 条记录") + ", "
            + String(localized: "\(selected?.reps ?? 0) 次")
    }

    private func color(for level: Int) -> Color {
        level == 0 ? Studio.line.opacity(0.65) : Studio.accent.opacity([0, 0.22, 0.44, 0.7, 1][level])
    }

    private func choose(_ date: Date, reveal: Bool = false) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            selectedDate = calendar.startOfDay(for: date)
            if reveal { scrollTarget = selectedDate }
        }
    }

    private func changeYear(_ year: Int?) {
        selectedYear = year
        selectedDate = nil
        scrollTarget = nil
    }

    private func openSelection() {
        guard selected != nil, let end = calendar.date(byAdding: .day, value: 1, to: selection) else { return }
        openDay(DateInterval(start: selection, end: end))
    }
}
