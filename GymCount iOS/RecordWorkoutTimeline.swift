import SwiftUI
import Charts

// A single time coordinate is shared by the curves, event rail and repetition list.
// Channel names describe the measurements actually recorded by Core Motion.
private enum WorkoutSensorChannel: String, CaseIterable, Identifiable {
    case acceleration, userAcceleration, rotation, attitude, gravity, magneticField
    var id: String { rawValue }
    var title: String { switch self {
        case .acceleration: String(localized: "加速度")
        case .userAcceleration: String(localized: "去重力加速度")
        case .rotation: String(localized: "旋转速率")
        case .attitude: String(localized: "姿态角")
        case .gravity: String(localized: "重力")
        case .magneticField: String(localized: "融合磁场")
    } }
    var unit: String { switch self {
        case .acceleration, .userAcceleration, .gravity: "g"
        case .rotation: "rad/s"
        case .attitude: "°"
        case .magneticField: "µT"
    } }
    var axes: [String] { self == .attitude ? ["Roll", "Pitch", "Yaw"] : ["X", "Y", "Z"] }
    static func available(in timeline: WorkoutTimeline) -> [Self] {
        var result: [Self] = timeline.acceleration.isEmpty ? [] : [.acceleration]
        if !timeline.motion.isEmpty { result += [.userAcceleration, .rotation, .attitude, .gravity] }
        if timeline.motion.contains(where: { $0.magneticField != nil }) { result.append(.magneticField) }
        return result
    }
    func vectors(in timeline: WorkoutTimeline) -> [WorkoutSensorVector] {
        switch self {
        case .acceleration: return timeline.acceleration.map { .init(t: $0.t, x: $0.x, y: $0.y, z: $0.z) }
        case .userAcceleration: return timeline.motion.map { .init(t: $0.t, x: $0.userAcceleration.x, y: $0.userAcceleration.y, z: $0.userAcceleration.z) }
        case .rotation: return timeline.motion.map { .init(t: $0.t, x: $0.rotationRate.x, y: $0.rotationRate.y, z: $0.rotationRate.z) }
        case .attitude: return timeline.motion.map { .init(t: $0.t, x: $0.attitude.x * 180 / .pi, y: $0.attitude.y * 180 / .pi, z: $0.attitude.z * 180 / .pi) }
        case .gravity: return timeline.motion.map { .init(t: $0.t, x: $0.gravity.x, y: $0.gravity.y, z: $0.gravity.z) }
        case .magneticField: return timeline.motion.compactMap { sample in sample.magneticField.map { .init(t: sample.t, x: $0.x, y: $0.y, z: $0.z) } }
        }
    }
}

private struct WorkoutSensorVector {
    let t: Double
    let x: Double
    let y: Double
    let z: Double
    subscript(axis: Int) -> Double { axis == 0 ? x : axis == 1 ? y : z }
}

private enum WorkoutEventSource: String, CaseIterable, Identifiable {
    case detected, reference, feedback
    var id: String { rawValue }
    var title: String { switch self {
        case .detected: String(localized: "识别打点")
        case .reference: String(localized: "人工标注")
        case .feedback: String(localized: "震动请求")
    } }
    var symbol: String { switch self {
        case .detected: "circle.fill"
        case .reference: "diamond.fill"
        case .feedback: "waveform.path"
    } }
    func times(in timeline: WorkoutTimeline) -> [Double] { switch self {
        case .detected: timeline.detectedEvents
        case .reference: timeline.referenceEvents ?? []
        case .feedback: timeline.feedbackEvents ?? []
    } }
    static func available(in timeline: WorkoutTimeline) -> [Self] {
        allCases.filter { !$0.times(in: timeline).isEmpty }
    }
}

private struct WorkoutCurvePoint: Identifiable {
    let index: Int
    let axis: Int
    let time: Double
    let value: Double
    let segment: Int
    var id: Int { index * 3 + axis }
    var series: String { "\(axis)-\(segment)" }
}

// These are view coordinates only. Set membership and timestamps always come
// from the displayed report, including the phone's split/merge corrections.
struct RecordSetRegion: Identifiable {
    let id: UUID
    let number: Int
    let firstCompletion: Double
    let lastCompletion: Double

    var title: String {
        String(format: NSLocalizedString("Set %ld", tableName: "WholeWorkout", comment: ""), number)
    }

    func intersects(_ range: ClosedRange<Double>) -> Bool {
        lastCompletion >= range.lowerBound && firstCompletion <= range.upperBound
    }

    static func make(sets: [WorkoutReport.SetRecord], origin: Date,
                     exercise: ExerciseType? = nil) -> [Self] {
        sets.enumerated().compactMap { index, set in
            guard exercise == nil || set.exercise == exercise,
                  let first = set.repetitions.first?.completedAt,
                  let last = set.repetitions.last?.completedAt else { return nil }
            return Self(id: set.id, number: index + 1,
                        firstCompletion: first.timeIntervalSince(origin),
                        lastCompletion: last.timeIntervalSince(origin))
        }
    }
}

// Pure drawing: the plot geometry is never written into view state. The label
// band has its own space above the data, but shares the same shaded interval.
struct RecordSetRegionBackdrop: View {
    let regions: [RecordSetRegion]
    let visible: ClosedRange<Double>
    let plotFrame: CGRect
    let labelHeight: CGFloat

    private var displayed: [RecordSetRegion] { regions.filter { $0.intersects(visible) } }
    private func position(_ time: Double) -> CGFloat {
        plotFrame.minX + (time - visible.lowerBound) / (visible.upperBound - visible.lowerBound) * plotFrame.width
    }

    var body: some View {
        let displayed = self.displayed
        ZStack(alignment: .topLeading) {
            ForEach(displayed) { region in
                let left = position(max(visible.lowerBound, region.firstCompletion))
                let right = position(min(visible.upperBound, region.lastCompletion))
                let width = max(0, right - left)
                Rectangle().fill(Studio.accent.opacity(region.number.isMultiple(of: 2) ? 0.10 : 0.065))
                    .frame(width: width, height: plotFrame.height + labelHeight)
                    .position(x: (left + right) / 2, y: plotFrame.midY - labelHeight / 2)
                // Never enlarge a one-rep set into an invented time interval.
                // Narrow labels disappear in the overview and return on zoom.
                // A one-point set has no band width: its label sits immediately
                // beside that boundary only when no other labels can collide.
                if region.firstCompletion == region.lastCompletion, displayed.count == 1 {
                    let toRight = left <= plotFrame.midX
                    let labelWidth = max(0, (toRight ? plotFrame.maxX - left : left - plotFrame.minX) - 8)
                    ViewThatFits(in: .horizontal) {
                        Text(region.title).font(Studio.Fonts.axis).foregroundStyle(Studio.accent).fixedSize()
                        Color.clear
                    }
                    .frame(width: labelWidth, height: labelHeight, alignment: toRight ? .leading : .trailing)
                    .position(x: left + (toRight ? 1 : -1) * (labelWidth / 2 + 4),
                              y: plotFrame.minY - labelHeight / 2)
                } else {
                    ViewThatFits(in: .horizontal) {
                        Text(region.title).font(Studio.Fonts.axis).foregroundStyle(Studio.accent).fixedSize()
                        Color.clear
                    }
                    .frame(width: max(0, width - 8), height: labelHeight)
                    .position(x: (left + right) / 2, y: plotFrame.minY - labelHeight / 2)
                }
            }
            // Equal first/last points, including adjacent sets sharing a
            // completion timestamp, contribute one crisp boundary, not a stack.
            Path { path in
                let boundaries = Set(displayed.flatMap { [$0.firstCompletion, $0.lastCompletion] })
                for time in boundaries where visible.contains(time) {
                    let x = position(time)
                    path.move(to: CGPoint(x: x, y: plotFrame.minY - labelHeight))
                    path.addLine(to: CGPoint(x: x, y: plotFrame.maxY))
                }
            }.stroke(Studio.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct RecordWorkoutTimeline: View {
    let timeline: WorkoutTimeline
    var title = String(localized: "时间轴")
    var timeOffset: TimeInterval = 0
    var usesSegmentTime = false
    var segmentPicker: AnyView?
    var setRegions: [RecordSetRegion] = []
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var eventAccessoryWidth: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var setLabelHeight: CGFloat = 24
    @State private var channel = WorkoutSensorChannel.acceleration
    @State private var eventSource = WorkoutEventSource.detected
    @State private var selectedTime: Double?
    @State private var gestureTime: Double?
    @State private var windowSeconds: Double = 0
    @State private var windowAnchor: Double = 0
    @State private var vectors: [WorkoutSensorVector] = []
    @State private var curve: [WorkoutCurvePoint] = []
    @State private var expanded = false

    private var channels: [WorkoutSensorChannel] { WorkoutSensorChannel.available(in: timeline) }
    private var sources: [WorkoutEventSource] { WorkoutEventSource.available(in: timeline) }
    private var events: [Double] { eventSource.times(in: timeline) }
    private var extent: Double { max(1, timeline.duration) }
    private var visibleSetRegions: [RecordSetRegion] { setRegions.filter { $0.intersects(visible) } }
    private var visible: ClosedRange<Double> {
        guard windowSeconds > 0, windowSeconds < extent else { return 0...extent }
        let start = min(max(0, windowAnchor - windowSeconds / 2), extent - windowSeconds)
        return start...(start + windowSeconds)
    }
    private var selectedRep: Int? {
        guard let selectedTime else { return nil }
        return events.indices.min(by: { abs(events[$0] - selectedTime) < abs(events[$1] - selectedTime) })
            .flatMap { abs(events[$0] - selectedTime) < 0.15 ? $0 : nil }
    }
    private var inspected: WorkoutSensorVector? {
        guard let selectedTime else { return nil }
        // Never interpolate across missing samples or between independent streams.
        var low = 0, high = vectors.count
        while low < high {
            let mid = (low + high) / 2
            if vectors[mid].t < selectedTime { low = mid + 1 } else { high = mid }
        }
        let candidates = [low - 1, low].filter { vectors.indices.contains($0) }
        guard let index = candidates.min(by: { abs(vectors[$0].t - selectedTime) < abs(vectors[$1].t - selectedTime) }),
              abs(vectors[index].t - selectedTime) <= 0.15 else { return nil }
        return vectors[index]
    }
    private var yDomain: ClosedRange<Double> {
        let values = curve.map(\.value)
        let low = values.min() ?? -1, high = values.max() ?? 1
        let padding = max(0.05, (high - low) * 0.12)
        return (low - padding)...(high + padding)
    }
    private let axisColors = [Studio.accent, Studio.adaptive(0x356E75, 0x8FC2C7), Studio.adaptive(0x946259, 0xD1A095)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let segmentPicker { segmentPicker }
            if !channels.isEmpty {
                inspector
                sensorChart
                chartFooter
            }
            if !events.isEmpty { repetitionList }
            if timeline.isPartial {
                Label(String(localized: "部分采样"), systemImage: "circle.lefthalf.filled")
                    .font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
            }
        }.padding(.vertical, 8)
            .onAppear { prepare() }
            .onChange(of: channel) { _, _ in vectors = channel.vectors(in: timeline); prepareCurve() }
            .onChange(of: windowSeconds) { _, _ in windowAnchor = selectedTime ?? windowSeconds / 2; prepareCurve() }
            .onChange(of: selectedTime) { _, value in
                if let value, !value.isFinite { selectedTime = nil }
            }
            .onChange(of: gestureTime) { _, value in
                // Charts clears its transient gesture binding on touch-up. Keep
                // the inspected point until the user explicitly clears it.
                if let value, value.isFinite { selectedTime = min(visible.upperBound, max(visible.lowerBound, value)) }
            }
            .onChange(of: timeline) { _, _ in selectedTime = nil; prepare() }
    }

    private var header: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center))) {
            Text(title).font(Studio.Fonts.section)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if !channels.isEmpty {
                Menu {
                    ForEach(channels) { value in
                        Button { channel = value } label: {
                            if channel == value { Label(value.title, systemImage: "checkmark") } else { Text(value.title) }
                        }.accessibilityIdentifier("timeline-channel-\(value.rawValue)")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(channel.title).font(Studio.Fonts.body.weight(.medium))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }.frame(minHeight: Studio.controlHeight)
                }.accessibilityLabel(String(localized: "传感器"))
                    .accessibilityValue(channel.title).accessibilityIdentifier("timeline-channel")
            }
        }
    }

    private var inspector: some View {
        let sample = inspected
        return (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))) {
                ForEach(0..<3, id: \.self) { axis in
                    HStack(spacing: 5) {
                        Circle().fill(axisColors[axis]).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(channel.axes[axis]).font(Studio.Fonts.control)
                        if let sample { Text(sample[axis], format: .number.precision(.fractionLength(2))).font(Studio.Fonts.caption.monospacedDigit()) }
                    }.foregroundStyle(Studio.ink)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(channel.axes[axis])
                        .accessibilityValue(sample.map { $0[axis].formatted(.number.precision(.fractionLength(2))) + " " + channel.unit } ?? channel.unit)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if usesSegmentTime {
                    Text(String(localized: "段内时间")).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
                }
                Text(channel.unit).font(Studio.Fonts.caption).foregroundStyle(Studio.muted)
        }.accessibilityIdentifier("timeline-axis-values")
    }

    private var sensorChart: some View {
        Chart {
            ForEach(curve) { point in
                LineMark(x: .value("Time", point.time), y: .value(channel.unit, point.value), series: .value("Axis", point.series))
                    .foregroundStyle(axisColors[point.axis]).lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            ForEach(Array(events.enumerated()), id: \.offset) { _, time in
                if visible.contains(time) {
                    RuleMark(x: .value("Event", time))
                        .foregroundStyle(Studio.accent.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                        .accessibilityLabel(eventSource.title)
                        .accessibilityValue(timecode(time, precise: true))
                }
            }
            if let time = selectedTime, visible.contains(time) {
                RuleMark(x: .value("Selection", time)).foregroundStyle(Studio.ink.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }.chartXScale(domain: visible, range: .plotDimension(startPadding: 0, endPadding: 0))
            .chartYScale(domain: yDomain)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        RecordSetRegionBackdrop(regions: setRegions, visible: visible,
                                                plotFrame: geometry[anchor], labelHeight: setLabelHeight)
                    }
                }.allowsHitTesting(false)
            }
            .chartXSelection(value: $gestureTime)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Studio.line.opacity(0.6))
                    AxisValueLabel { if let seconds = value.as(Double.self) { Text(timecode(seconds)).font(Studio.Fonts.axis.monospacedDigit()).foregroundStyle(Studio.muted) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Studio.line.opacity(0.6))
                    AxisValueLabel { if let number = value.as(Double.self) { Text(number, format: .number.precision(.fractionLength(0...1))).font(Studio.Fonts.axis).foregroundStyle(Studio.muted) } }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if !events.isEmpty, let anchor = proxy.plotFrame {
                        eventRail(plotFrame: geometry[anchor], y: geometry.size.height + 10)
                    }
                }.allowsHitTesting(false)
            }
            .frame(height: typeSize.isAccessibilitySize ? 200 : 180)
            .padding(.top, visibleSetRegions.isEmpty ? 0 : setLabelHeight)
            .padding(.bottom, events.isEmpty ? 0 : 20)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(channel.title)
            .accessibilityValue(chartAccessibilityValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: select(min(extent, (selectedTime ?? 0) + 1))
                case .decrement: select(max(0, (selectedTime ?? 0) - 1))
                @unknown default: break
                }
            }
            .accessibilityIdentifier("workout-sensor-chart")
    }

    private var chartAccessibilityValue: String {
        let cursor = selectedTime.map { timecode($0, precise: true) } ?? "\(timecode(visible.lowerBound)) – \(timecode(visible.upperBound))"
        let groups = visibleSetRegions.map { region in
            "\(region.title), \(timecode(region.firstCompletion, precise: true)) – \(timecode(region.lastCompletion, precise: true))"
        }
        return ([cursor] + groups).joined(separator: "; ")
    }

    // Read geometry where the rail is drawn. Writing it into parent view state
    // restarts Chart layout during menu presentation and List transitions.
    private func eventRail(plotFrame: CGRect, y: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: plotFrame.minX, y: y))
                path.addLine(to: CGPoint(x: plotFrame.maxX, y: y))
            }.stroke(Studio.line, lineWidth: 1)
            ForEach(Array(events.enumerated()), id: \.offset) { index, time in
                if visible.contains(time) {
                    Image(systemName: eventSource.symbol).font(.system(size: selectedRep == index ? 9 : 6, weight: .semibold))
                        .foregroundStyle(selectedRep == index ? Studio.ink : Studio.accent)
                        .position(x: plotFrame.minX + (time - visible.lowerBound) / (visible.upperBound - visible.lowerBound) * plotFrame.width, y: y)
                }
            }
        }.accessibilityHidden(true)
    }

    private var chartFooter: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))) {
            if windowSeconds > 0 {
                Button { moveWindow(-1) } label: { Image(systemName: "chevron.left").frame(width: Studio.controlHeight, height: Studio.controlHeight) }
                    .disabled(visible.lowerBound == 0).accessibilityLabel(String(localized: "上一时段"))
                    .accessibilityIdentifier("timeline-previous-window")
            }
            if typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 8) {
                    cursorTime
                    Spacer(minLength: 0)
                    clearSelection
                        .opacity(selectedTime == nil ? 0 : 1)
                        .disabled(selectedTime == nil)
                        .accessibilityHidden(selectedTime == nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                cursorTime
                if selectedTime != nil { clearSelection }
            }
            if windowSeconds > 0 {
                Button { moveWindow(1) } label: { Image(systemName: "chevron.right").frame(width: Studio.controlHeight, height: Studio.controlHeight) }
                    .disabled(visible.upperBound == extent).accessibilityLabel(String(localized: "下一时段"))
                    .accessibilityIdentifier("timeline-next-window")
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Menu {
                ForEach([0.0, 15.0, 30.0], id: \.self) { value in
                    if value == 0 || value < extent {
                        Button(value == 0 ? String(localized: "全程") : String(localized: "\(Int(value)) 秒")) { windowSeconds = value }
                            .accessibilityIdentifier("timeline-window-\(Int(value))")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: windowSeconds > 0 ? "minus.magnifyingglass" : "plus.magnifyingglass")
                    Text(windowSeconds == 0 ? String(localized: "全程") : String(localized: "\(Int(windowSeconds)) 秒"))
                }.font(Studio.Fonts.control).frame(minHeight: Studio.controlHeight)
            }.accessibilityIdentifier("timeline-window")
        }
    }

    private var cursorTime: some View {
        Text(selectedTime.map { timecode($0, precise: true) } ?? "\(timecode(visible.lowerBound)) – \(timecode(visible.upperBound))")
            .font(Studio.Fonts.caption.monospacedDigit()).foregroundStyle(Studio.muted)
            .minimumScaleFactor(0.85)
            .accessibilityLabel(String(localized: "时间"))
            .accessibilityValue(selectedTime.map { timecode($0, precise: true) } ?? "\(timecode(visible.lowerBound)) – \(timecode(visible.upperBound))")
            .accessibilityIdentifier("timeline-cursor-time")
    }

    private var clearSelection: some View {
        Button { selectedTime = nil } label: {
            Image(systemName: "xmark.circle.fill").font(.body)
                .frame(width: Studio.controlHeight, height: Studio.controlHeight)
        }.foregroundStyle(Studio.muted).accessibilityLabel(String(localized: "清除选中"))
            .accessibilityIdentifier("timeline-clear-selection")
    }

    private var repetitionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())) {
                if sources.count > 1 {
                    Menu {
                        ForEach(sources) { source in
                            Button(source.title) { eventSource = source; selectedTime = nil }
                                .accessibilityIdentifier("timeline-event-source-\(source.rawValue)")
                        }
                    } label: {
                        HStack(spacing: 5) { Text(eventSource.title); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
                            .font(Studio.Fonts.body.weight(.medium)).frame(minHeight: Studio.controlHeight)
                    }.accessibilityIdentifier("timeline-event-source")
                } else { Text(eventSource.title).font(Studio.Fonts.body.weight(.medium)).frame(minHeight: Studio.controlHeight) }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(String(localized: "\(events.count) 次")).font(Studio.Fonts.body.monospacedDigit()).foregroundStyle(Studio.muted)
            }
            Divider().overlay(Studio.line)
            ForEach(Array(events.enumerated()).prefix(expanded ? events.count : 6), id: \.offset) { index, time in
                Button { select(time) } label: {
                    HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
                        Text((index + 1).formatted(.number.precision(.integerLength(2))))
                            .font(Studio.Fonts.caption.monospacedDigit()).foregroundStyle(selectedRep == index ? Studio.accent : Studio.muted)
                            .frame(minWidth: 24, alignment: .leading)
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())) {
                            Text(timecode(time, precise: true)).font(Studio.Fonts.body.monospacedDigit()).foregroundStyle(Studio.ink)
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                            if index > 0 {
                                Text(String(localized: "间隔 \((time - events[index - 1]).formatted(.number.precision(.fractionLength(2)))) 秒"))
                                    .font(Studio.Fonts.caption.monospacedDigit()).foregroundStyle(Studio.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        Image(systemName: selectedRep == index ? "scope" : "chevron.right")
                            .font(Studio.Fonts.axis).foregroundStyle(selectedRep == index ? Studio.accent : Studio.muted)
                            .frame(width: typeSize.isAccessibilitySize ? eventAccessoryWidth : nil)
                    }
                    // The interval already asks for its full wrapped height.
                    // Give the entire row that same intrinsic height, otherwise
                    // List can compress its HStack while the text overflows it.
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                    .frame(minHeight: Studio.controlHeight).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "第 \(index + 1) 次"))
                    .accessibilityValue(timecode(time, precise: true))
                    .accessibilityAddTraits(selectedRep == index ? .isSelected : [])
                    .accessibilityIdentifier("timeline-rep-\(index + 1)")
                Divider().overlay(Studio.line.opacity(0.6))
            }
            if events.count > 6 {
                Button(expanded ? String(localized: "收起") : String(localized: "全部 \(events.count) 次")) {
                    withAnimation(RecordMotion.animation(reduced: reduceMotion)) { expanded.toggle() }
                }.font(Studio.Fonts.body).frame(minHeight: Studio.controlHeight).accessibilityIdentifier("timeline-expand-reps")
            }
        }.fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
    }

    private func select(_ time: Double) {
        selectedTime = time
        if windowSeconds > 0 { windowAnchor = time; prepareCurve() }
    }
    private func moveWindow(_ direction: Double) {
        let center = (visible.lowerBound + visible.upperBound) / 2
        windowAnchor = min(extent - windowSeconds / 2, max(windowSeconds / 2, center + direction * windowSeconds * 0.75))
        selectedTime = nil; prepareCurve()
    }
    private func prepare() {
        if !channels.contains(channel), let first = channels.first { channel = first }
        if !sources.contains(eventSource), let first = sources.first { eventSource = first }
        vectors = channel.vectors(in: timeline)
        prepareCurve()
    }
    private func prepareCurve() {
        let input = vectors.enumerated().filter { visible.contains($0.element.t) }
        // Preserve each axis's extrema in every bucket. This bounds drawing work
        // without smoothing away brief movement peaks. Raw files remain unchanged.
        let stride = max(1, Int(ceil(Double(input.count) / 400)))
        var runs: [[(offset: Int, element: WorkoutSensorVector)]] = []
        for sample in input {
            if let previous = runs.last?.last, sample.element.t - previous.element.t <= 0.25 {
                runs[runs.count - 1].append(sample)
            } else { runs.append([sample]) }
        }
        var points: [WorkoutCurvePoint] = []
        for axis in 0..<3 {
            for (segment, run) in runs.enumerated() {
                for start in Swift.stride(from: 0, to: run.count, by: stride) {
                    let bucket = Array(run[start..<min(start + stride, run.count)])
                    let extrema = [bucket.first!, bucket.min(by: { $0.element[axis] < $1.element[axis] })!,
                                   bucket.max(by: { $0.element[axis] < $1.element[axis] })!, bucket.last!]
                    var included = Set<Int>()
                    for sample in extrema.sorted(by: { $0.offset < $1.offset }) where included.insert(sample.offset).inserted {
                        points.append(.init(index: sample.offset, axis: axis, time: sample.element.t, value: sample.element[axis], segment: segment))
                    }
                }
            }
        }
        curve = points
    }
    private func timecode(_ seconds: Double, precise: Bool = false) -> String {
        let value = max(0, seconds + timeOffset)
        let hours = Int(value) / 3600, minutes = (Int(value) / 60) % 60
        let second = precise ? String(format: "%05.2f", value.truncatingRemainder(dividingBy: 60)) : String(format: "%02d", Int(value) % 60)
        return hours > 0 ? "\(hours):\(String(format: "%02d", minutes)):\(second)" : "\(Int(value) / 60):\(second)"
    }
}

// Load only the selected recording block. Each block keeps its own sample clock;
// labels add its offset from the whole workout so pauses and exercise changes
// never collapse onto the same zero on the report's timeline.
struct RecordReportSensors: View {
    let id: UUID
    let startedAt: Date
    let sets: [WorkoutReport.SetRecord]
    @EnvironmentObject private var store: PhoneWorkoutStore
    #if GYMCOUNT_SYNC
    @EnvironmentObject private var capture: PhoneCaptureStore
    #endif
    @State private var segments: [WorkoutReportSensorSummary] = []
    @State private var selectedSegmentID: UUID?
    @State private var timeline: WorkoutTimeline?
    @State private var loadingIndex = true
    @State private var loadingSegment = false
    @State private var indexFailed = false
    @State private var segmentFailed = false
    @State private var reloadID = UUID()
    @State private var requestedSensors = false

    private var selection: WorkoutReportSensorSummary? {
        segments.first { $0.id == selectedSegmentID }
    }

    var body: some View {
        // Keep the loading tasks on one stable view. A Group distributes its
        // modifiers to each conditional branch, which would restart loading
        // whenever clearing/replacing timeline swaps the visible branch.
        VStack(alignment: .leading, spacing: 0) {
            if !indexFailed, let timeline, let selection, timeline.id == selection.id {
                RecordWorkoutTimeline(timeline: timeline, title: String(localized: "传感器"),
                                      timeOffset: (timeline.origin ?? selection.origin).map { $0.timeIntervalSince(startedAt) } ?? 0,
                                      usesSegmentTime: timeline.origin == nil && selection.origin == nil,
                                      segmentPicker: segments.count > 1 ? AnyView(segmentMenu) : nil,
                                      setRegions: regions(for: timeline, selection: selection))
                    .id(selection.id)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "传感器")).font(Studio.Fonts.section)
                    if segments.count > 1 { segmentMenu }
                    if loadingIndex || loadingSegment {
                        ProgressView().frame(minHeight: Studio.controlHeight)
                            .accessibilityLabel(String(localized: "正在读取采样"))
                            .accessibilityIdentifier("report-sensor-loading")
                    } else if indexFailed || segmentFailed {
                        HStack(spacing: 12) {
                            Text(String(localized: "采样无法读取")).foregroundStyle(Studio.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button(String(localized: "重试")) { reloadID = UUID() }
                                .frame(minHeight: Studio.controlHeight)
                                .accessibilityIdentifier("report-sensor-retry")
                        }.font(Studio.Fonts.body)
                    } else {
                        missingSamples
                    }
                }.padding(.vertical, 8)
            }
        }
        .task(id: "\(id)/\(store.timelineRevision)/\(reloadID)") { await loadIndex() }
        .task(id: "\(selectedSegmentID?.uuidString ?? "none")/\(store.timelineRevision)/\(reloadID)") { await loadSelectedSegment() }
    }

    private func regions(for timeline: WorkoutTimeline, selection: WorkoutReportSensorSummary) -> [RecordSetRegion] {
        // The segment's source date is not the first sample's clock anchor.
        // Without the retained origin, keep the curves on segment time only.
        guard let origin = timeline.origin ?? selection.origin,
              let exercise = ExerciseType(rawValue: timeline.source.exercise) else { return [] }
        return RecordSetRegion.make(sets: sets, origin: origin, exercise: exercise)
    }

    private var segmentMenu: some View {
        Menu {
            ForEach(segments) { segment in
                Button {
                    selectedSegmentID = segment.id
                } label: {
                    if segment.id == selectedSegmentID {
                        Label(segmentTitle(segment), systemImage: "checkmark")
                    } else { Text(segmentTitle(segment)) }
                }.accessibilityIdentifier("report-sensor-segment-\(segment.id)")
            }
        } label: {
            HStack(spacing: 6) {
                if let selection { Text(segmentTitle(selection)) }
                Image(systemName: "chevron.down").font(Studio.Fonts.axis)
            }.font(Studio.Fonts.control).frame(minHeight: Studio.controlHeight)
        }.accessibilityLabel(String(localized: "采样段"))
            .accessibilityValue(selection.map(segmentTitle) ?? "")
            .accessibilityIdentifier("report-sensor-segments")
    }

    private func segmentTitle(_ segment: WorkoutReportSensorSummary) -> String {
        let name = ExerciseType(rawValue: segment.source.exercise)?.displayName ?? String(localized: "训练")
        guard let origin = segment.origin else { return name }
        let elapsed = max(0, origin.timeIntervalSince(startedAt))
        let time = Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond))
        return name + " · " + time
    }

    private var missingSamples: some View {
        HStack(spacing: 12) {
            #if GYMCOUNT_SYNC
            Text(missingStatus).foregroundStyle(Studio.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("report-sensor-missing-status")
            Spacer(minLength: 0)
            Button(String(localized: "同步")) {
                capture.requestWorkoutHistory(force: true, timelineID: id)
            }.frame(minWidth: Studio.controlHeight, minHeight: Studio.controlHeight)
                .accessibilityIdentifier("report-sensor-sync")
            #else
            Text(String(localized: "无传感器采样")).foregroundStyle(Studio.muted)
                .accessibilityIdentifier("report-sensor-missing-status")
            #endif
        }.font(Studio.Fonts.body)
    }

    #if GYMCOUNT_SYNC
    private var missingStatus: String {
        if capture.unavailableTimelineIDs.contains(id) { return String(localized: "无传感器采样") }
        switch capture.workoutSyncState {
        case .idle, .succeeded: return String(localized: "未接收采样")
        case .failed: return capture.workoutSyncMessage
        default: return capture.workoutSyncState.title
        }
    }
    #endif

    @MainActor private func loadIndex() async {
        loadingIndex = true
        do {
            let result = try await store.loadReportSensorIndex(id)
            guard !Task.isCancelled else { return }
            segments = result
            if !result.contains(where: { $0.id == selectedSegmentID }) {
                selectedSegmentID = result.first?.id
                timeline = nil
                segmentFailed = false
            }
            indexFailed = false; loadingIndex = false
            #if GYMCOUNT_SYNC
            if !requestedSensors {
                requestedSensors = true
                capture.requestWorkoutHistory(force: result.isEmpty, timelineID: id)
            }
            #endif
        } catch {
            guard !Task.isCancelled else { return }
            timeline = nil; indexFailed = true; loadingIndex = false
        }
    }

    @MainActor private func loadSelectedSegment() async {
        guard let selectedSegmentID else { loadingSegment = false; return }
        loadingSegment = true
        timeline = nil
        do {
            let result = try await store.loadReportSensor(id, segmentID: selectedSegmentID)
            guard !Task.isCancelled, self.selectedSegmentID == selectedSegmentID else { return }
            timeline = result
            segmentFailed = false; loadingSegment = false
        } catch {
            guard !Task.isCancelled, self.selectedSegmentID == selectedSegmentID else { return }
            segmentFailed = true; loadingSegment = false
        }
    }
}
