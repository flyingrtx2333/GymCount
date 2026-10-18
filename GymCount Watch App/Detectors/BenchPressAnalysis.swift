import Foundation

// Shared by Watch and iPhone. Input is sensor time and fused motion only;
// repetition labels, video markers and callback arrival time are never inputs.
struct BenchVector: Codable {
    let x: Double
    let y: Double
    let z: Double
    var value: SIMD3<Double> { SIMD3(x, y, z) }
}

struct BenchMotionSample: Decodable {
    let t: Double
    let gravity: BenchVector
    let user_acceleration: BenchVector
    let rotation_rate: BenchVector
}

struct BenchCycle: Codable, Equatable {
    let start: Double
    let turn: Double
    let end: Double
}

struct BenchAnalysis {
    static let version = "bench-top-return-20261018-v8"
    var cycles: [BenchCycle] = []
    var status = "needs_review"
    var lastCandidateEnd: Double?
    var count: Int? { status == "estimated" ? cycles.count : nil }
}

enum BenchPressAnalysis {
    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x*b.x + a.y*b.y + a.z*b.z
    }
    private static func norm(_ v: SIMD3<Double>) -> Double { sqrt(dot(v, v)) }
    private static func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        acos(max(-1, min(1, dot(a, b))))
    }
    private static func quantile(_ values: [Double], _ q: Double) -> Double {
        let sorted = values.sorted(), position = Double(values.count - 1)*q
        let lo = Int(position), hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (sorted[hi] - sorted[lo])*(position - Double(lo))
    }
    // Edge padding and odd centered windows match cloud v8. Centering requires
    // future samples, so live prefixes are estimates; finish() performs the final pass.
    private static func smooth(_ values: [Double], width: Int) -> [Double] {
        let radius = width/2
        var sum = Double(radius)*values[0] + values.prefix(radius + 1).reduce(0, +)
        if values.count <= radius { sum += Double(radius + 1 - values.count)*values.last! }
        var result = [Double](); result.reserveCapacity(values.count)
        for i in values.indices {
            if i > 0 {
                sum += values[min(values.count - 1, i + radius)] - values[max(0, i - radius - 1)]
            }
            result.append(sum/Double(width))
        }
        return result
    }

    static func analyze(_ samples: [BenchMotionSample], gridOrigin: Double? = nil) -> BenchAnalysis {
        var result = BenchAnalysis()
        guard samples.count >= 2, samples.last!.t - samples[0].t >= 3 else { return result }
        for i in samples.indices {
            let s = samples[i]
            guard [s.t, s.gravity.x, s.gravity.y, s.gravity.z, s.user_acceleration.x,
                   s.user_acceleration.y, s.user_acceleration.z, s.rotation_rate.x,
                   s.rotation_rate.y, s.rotation_rate.z].allSatisfy(\.isFinite), norm(s.gravity.value) >= 0.5,
                  i == 0 || (s.t > samples[i-1].t && s.t - samples[i-1].t <= 0.25) else {
                result.status = "insufficient_data"; return result
            }
        }
        let units = samples.map { $0.gravity.value/norm($0.gravity.value) }
        let accelerations = samples.indices.map { dot(samples[$0].user_acceleration.value, units[$0]) }
        let rotations = samples.map { norm($0.rotation_rate.value) }
        let first = gridOrigin.map { $0 + ceil((samples[0].t - $0)*40 - 1e-8)/40 } ?? samples[0].t
        let size = Int(floor((samples.last!.t - first)*40 + 1e-8)) + 1
        let times = (0..<size).map { first + Double($0)/40 }
        var upward = [Double](), rates = [Double](), posture = [SIMD3<Double>]()
        var cursor = 0
        for t in times {
            while cursor + 1 < samples.count - 1 && samples[cursor + 1].t < t { cursor += 1 }
            let next = cursor + 1
            let f = max(0, min(1, (t - samples[cursor].t)/(samples[next].t - samples[cursor].t)))
            let vector = units[cursor] + (units[next] - units[cursor])*f
            guard norm(vector) >= 0.5 else { result.status = "insufficient_data"; return result }
            posture.append(vector/norm(vector))
            upward.append(accelerations[cursor] + (accelerations[next] - accelerations[cursor])*f)
            rates.append(rotations[cursor] + (rotations[next] - rotations[cursor])*f)
        }
        upward = smooth(upward, width: 9)
        var integral = 0.0
        let integrated = upward.map { integral += $0*9.80665/40; return integral }
        let drift = smooth(integrated, width: 161)
        let velocity = integrated.indices.map { integrated[$0] - drift[$0] }
        var candidates: [(start: Int, turn: Int, end: Int)] = []
        var state = 0, start = 0, turn = 0
        for i in velocity.indices {
            let value = velocity[i]
            if state == 0 {
                if value <= -0.06 {
                    start = i
                    while start > 0 && velocity[start-1] < 0 { start -= 1 }
                    state = 1
                }
            } else if state == 1 {
                if value < 0 && velocity[i-1] >= 0 {
                    var reversal = i - 1
                    while reversal > start && velocity[reversal-1] >= 0 { reversal -= 1 }
                    if velocity[reversal..<i].reduce(0, +)/40 >= 0.04 { start = i }
                }
                if times[i] - times[start] > 10 { state = 0; continue }
                if value >= 0.08 {
                    turn = i
                    while turn > start && velocity[turn-1] > 0 { turn -= 1 }
                    state = 2
                }
            } else if value <= 0.025 {
                state = 0
                let down = -velocity[start..<turn].reduce(0) { $0 + min($1, 0) }/40
                let up = velocity[turn...i].reduce(0) { $0 + max($1, 0) }/40
                let duration = times[i] - times[start]
                guard (1...10).contains(duration), min(times[turn] - times[start], times[i] - times[turn]) >= 0.25,
                      min(down, up) >= 0.04, (0.35...2.5).contains(up/down),
                      posture[start...i].map({ angle($0, posture[start]) }).max()! <= 0.65,
                      quantile(Array(rates[start...i]), 0.9) <= 1.5 else { continue }
                candidates.append((start, turn, i))
            }
        }
        result.lastCandidateEnd = candidates.last.map { times[$0.end] }
        var bouts: [[(start: Int, turn: Int, end: Int)]] = []
        for item in candidates {
            if let last = bouts.last, times[item.start] - times[last.last!.end] <= 6,
               last.allSatisfy({ angle(posture[item.turn], posture[$0.turn]) <= 0.35 &&
                                angle(posture[item.start], posture[$0.start]) <= 0.15 }) {
                bouts[bouts.count-1].append(item)
            } else { bouts.append([item]) }
        }
        // Smooth each coordinate once. Projection is linear, avoiding a full
        // recording-sized convolution for every repetition on the Watch.
        let sx = smooth(posture.map(\.x), width: 9)
        let sy = smooth(posture.map(\.y), width: 9)
        let sz = smooth(posture.map(\.z), width: 9)
        for bout in bouts where bout.count >= 2 {
            var top = bout.reduce(SIMD3<Double>(repeating: 0)) { $0 + posture[$1.start] }
            top /= norm(top)
            var confirmed: [BenchCycle] = [], lastEnd = -1
            for (index, item) in bout.enumerated() {
                let start = max(item.start, lastEnd), hold = 8
                var stop = min(size - hold, start + 400 - hold)
                if index + 1 < bout.count { stop = min(stop, bout[index+1].turn - hold) }
                let direction = top - posture[item.turn], span = norm(direction)
                guard span >= 0.1, times[item.turn] - times[start] >= 0.25, stop > item.end + hold else { continue }
                let unit = direction/span
                func progress(_ k: Int) -> Double { sx[k]*unit.x + sy[k]*unit.y + sz[k]*unit.z }
                let peak = quantile((item.end..<stop).map(progress), 0.98), margin = 0.1*span
                for k in item.end..<stop {
                    if quantile((k...k+hold).map(progress), 0.1) >= peak - margin,
                       quantile((k...k+hold).map { angle(posture[$0], top) }, 0.9) <= 0.15 {
                        lastEnd = k + hold
                        confirmed.append(BenchCycle(start: times[start], turn: times[item.turn], end: times[lastEnd]))
                        break
                    }
                }
            }
            if confirmed.count >= 2 { result.cycles += confirmed }
        }
        if !result.cycles.isEmpty { result.status = "estimated" }
        return result
    }
}

// Sensor-time prefix replay, at most twice per second. Seal completed bouts
// after 16 s (10 s maximum candidate + 6 s bout gap). Never bridge missing data.
final class BenchPressStream {
    private var samples: [BenchMotionSample] = []
    private var sealed: [BenchCycle] = []
    private var gridOrigin: Double?
    private var lastAnalysis = -Double.infinity
    private var pendingCount = -1
    private var pendingSince = 0.0
    private(set) var latest = BenchAnalysis()
    private(set) var interrupted = false
    var lastTimestamp: Double? { samples.last?.t }
    func markInterrupted() { interrupted = true }

    func reset() {
        samples = []; sealed = []; lastAnalysis = -.infinity
        gridOrigin = nil
        pendingCount = -1; pendingSince = 0; latest = BenchAnalysis(); interrupted = false
    }
    func append(_ sample: BenchMotionSample) -> BenchAnalysis? {
        guard sample.t.isFinite else { interrupted = true; return nil }
        if gridOrigin == nil { gridOrigin = sample.t }
        if let last = samples.last {
            guard sample.t > last.t else { return nil }
            if sample.t - last.t > 0.25 {
                seal(); samples = []; interrupted = true
            }
        }
        samples.append(sample)
        guard sample.t - lastAnalysis >= 0.5 else { return nil }
        lastAnalysis = sample.t
        let result = combined()
        // Hide short-lived prefix count changes caused by the centered filter.
        // The final pass bypasses this presentation delay.
        if result.cycles.count != pendingCount {
            pendingCount = result.cycles.count; pendingSince = sample.t
        }
        if sample.t - pendingSince >= 1 { latest = result }
        let candidateEnd = result.lastCandidateEnd ?? samples[0].t
        if sample.t - candidateEnd > 16 || samples.count >= 19200 {
            seal()
            // Retain enough integration/phase context at an 8-minute boundary.
            let cutoff = sample.t - 12
            samples.removeAll { $0.t < cutoff }
        }
        return latest
    }
    func finish() -> BenchAnalysis { latest = combined(); return latest }
    private func seal() { sealed = combined().cycles }
    private func combined() -> BenchAnalysis {
        var result = BenchPressAnalysis.analyze(samples, gridOrigin: gridOrigin)
        let boundary = sealed.last?.turn ?? -.infinity
        result.cycles = sealed + result.cycles.filter { $0.turn > boundary + 0.5 }
        if !result.cycles.isEmpty { result.status = "estimated" }
        if interrupted { result.status = "insufficient_data" }
        return result
    }
}
