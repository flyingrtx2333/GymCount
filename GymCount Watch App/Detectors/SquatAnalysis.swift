import Foundation

struct SquatCycle: Codable {
    let start: Double
    let turn: Double
    let end: Double
}

// Matches the cloud's causal squat-stand-return-v1 implementation. Only fused
// sensor samples are inputs; no labels, video markers, or expected count.
final class SquatStream {
    static let version = "squat-stand-return-20261021-v1"
    private var last: Double?
    private var top: SIMD3<Double>?
    private var state = 0
    private var acceleration = 0.0, velocity = 0.0
    private var quiet: [(Double, SIMD3<Double>, Double, Double)] = []
    private var heldSince: Double?
    private var start = 0.0, turn = 0.0, down = 0.0, up = 0.0
    private var peakDown = 0.0, peakUp = 0.0
    private var braked = false

    private func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x*b.x + a.y*b.y + a.z*b.z }
    private func norm(_ v: SIMD3<Double>) -> Double { sqrt(dot(v, v)) }
    private func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { acos(max(-1, min(1, dot(a, b)))) }
    private func clearPhase() {
        top = nil; state = 0; acceleration = 0; velocity = 0
        quiet = []; heldSince = nil; start = 0; turn = 0; down = 0; up = 0
        peakDown = 0; peakUp = 0; braked = false
    }
    func reset() { clearPhase(); last = nil }

    func append(_ sample: BenchMotionSample) -> SquatCycle? {
        let values = [sample.t, sample.gravity.x, sample.gravity.y, sample.gravity.z,
                      sample.user_acceleration.x, sample.user_acceleration.y, sample.user_acceleration.z,
                      sample.rotation_rate.x, sample.rotation_rate.y, sample.rotation_rate.z]
        guard values.allSatisfy(\.isFinite), norm(sample.gravity.value) >= 0.5 else { reset(); return nil }
        guard let previous = last else { last = sample.t; return nil }
        guard sample.t > previous else { return nil }
        let dt = sample.t - previous; last = sample.t
        guard dt <= 0.25 else { clearPhase(); return nil }
        let gravity = sample.gravity.value/norm(sample.gravity.value)
        let rate = norm(sample.rotation_rate.value)
        let vertical = dot(sample.user_acceleration.value, gravity)*9.80665
        acceleration += (vertical - acceleration)*(1-exp(-dt/0.08))
        velocity = velocity*exp(-dt/1.5) + acceleration*dt
        quiet.append((sample.t, gravity, acceleration, rate))
        quiet.removeAll { sample.t - $0.0 > 0.5 }
        let stable = sample.t - quiet[0].0 >= 0.35 && quiet.allSatisfy {
            abs($0.2) < 0.5 && $0.3 < 0.8 && angle(gravity, $0.1) < 0.10
        }
        if state == 0 {
            if stable { top = gravity; velocity = 0 }
            if top != nil, velocity < -0.15, acceleration < -0.6 {
                state = 1; start = sample.t; down = 0; up = 0
                braked = false; heldSince = nil; peakDown = velocity; peakUp = 0
            }
            return nil
        }
        peakDown = min(peakDown, velocity); peakUp = max(peakUp, velocity)
        guard let top, sample.t - start <= 10, angle(gravity, top) <= 0.4, rate <= 2 else {
            clearPhase(); return nil
        }
        if state == 1 {
            down += max(0, -velocity)*dt
            if velocity > 0.12, sample.t - start > 0.3 { state = 2; turn = sample.t }
        } else {
            up += max(0, velocity)*dt
            if acceleration < -0.7 { braked = true }
            let completed = braked && abs(acceleration) < 0.8 && rate < 0.8 &&
                angle(gravity, top) < 0.25 && velocity < 0.2 && sample.t - turn > 0.3 &&
                min(down, up) > 0.12 && peakDown < -0.25 && peakUp > 0.25 &&
                up/down > 0.35 && up/down < 2.5 && sample.t - start > 1
            if completed {
                if heldSince == nil { heldSince = sample.t }
                if sample.t - heldSince! >= 0.15 {
                    let cycle = SquatCycle(start: start, turn: turn, end: sample.t)
                    state = 0; velocity = 0; acceleration = 0; heldSince = nil; self.top = gravity
                    return cycle
                }
            } else { heldSince = nil }
        }
        return nil
    }
}
