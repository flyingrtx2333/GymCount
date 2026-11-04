import Foundation

extension ExerciseType {
    var countingAlgorithmVersion: String {
        switch self {
        case .benchPress: BenchAnalysis.version
        case .squat: SquatStream.version
        case .deadlift: "rules-20261007"
        case .overheadPress, .barbellRow, .bicepCurl: UpperBodyDetector.version
        }
    }
    var completionFeedbackVersion: String? {
        switch self {
        case .benchPress: BenchPressFeedback.version
        case .deadlift: nil
        default: countingAlgorithmVersion
        }
    }
}

struct UpperBodyCycle: Equatable {
    let start: Double
    let end: Double
}

// Streaming rules for the selected movement, not exercise recognition. Only a
// qualified upward stroke can complete; lowering rearms the next repetition.
final class UpperBodyDetector {
    static let version = "upper-body-live-20261104-v1"
    let exercise: ExerciseType
    private(set) var cycles: [UpperBodyCycle] = []
    private(set) var interrupted = false
    var repCount: Int { cycles.count }

    private enum Phase { case ready, lifting, returning }
    private var phase = Phase.ready
    private var lastTime: Double?
    private var home: SIMD3<Double>?
    private var quietSince: Double?
    private var quietGravity: SIMD3<Double>?
    private var bias = 0.0
    private var acceleration = 0.0, velocity = 0.0, travel = 0.0
    private var peakTravel = 0.0, peakSpeed = 0.0, peakAngle = 0.0
    private var startedAt = 0.0, returnTravel = 0.0
    private var topSince: Double?
    private var followingCompletion = false
    private var nextStart: Double?

    init?(exercise: ExerciseType) {
        guard [.overheadPress, .barbellRow, .bicepCurl].contains(exercise) else { return nil }
        self.exercise = exercise
    }

    // ponytail: initial physical thresholds need wrist/video calibration with
    // these three movements; no accuracy claim is inferred from the old lifts.
    private var minimumTravel: Double {
        switch exercise {
        case .overheadPress: 0.14
        case .barbellRow: 0.08
        default: 0.07
        }
    }
    private var minimumLiftTime: Double { exercise == .overheadPress ? 0.35 : 0.25 }

    func resetCount() {
        cycles = []; interrupted = false; lastTime = nil
        clearPhase()
    }

    func markInterrupted() {
        interrupted = true; lastTime = nil
        clearPhase()
    }

    private func clearPhase() {
        phase = .ready; home = nil; quietSince = nil; quietGravity = nil
        bias = 0; acceleration = 0; velocity = 0; travel = 0
        peakTravel = 0; peakSpeed = 0; peakAngle = 0; returnTravel = 0; topSince = nil
        followingCompletion = false; nextStart = nil
    }

    private func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x*b.x + a.y*b.y + a.z*b.z }
    private func norm(_ v: SIMD3<Double>) -> Double { sqrt(dot(v, v)) }
    private func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { acos(max(-1, min(1, dot(a, b)))) }

    func append(_ sample: BenchMotionSample) -> UpperBodyCycle? {
        let values = [sample.t, sample.gravity.x, sample.gravity.y, sample.gravity.z,
                      sample.user_acceleration.x, sample.user_acceleration.y, sample.user_acceleration.z,
                      sample.rotation_rate.x, sample.rotation_rate.y, sample.rotation_rate.z]
        guard values.allSatisfy(\.isFinite), (0.5...1.5).contains(norm(sample.gravity.value)),
              norm(sample.user_acceleration.value) <= 4 else { markInterrupted(); return nil }
        guard let previous = lastTime else { lastTime = sample.t; return nil }
        guard sample.t > previous, sample.t - previous <= 0.25 else { markInterrupted(); return nil }
        let dt = sample.t - previous
        lastTime = sample.t
        let gravity = sample.gravity.value / norm(sample.gravity.value)
        let rate = norm(sample.rotation_rate.value)
        // Gravity points downward. This projection is independent of crown side
        // and wrist rotation; raw device X/Y/Z are never treated as world up.
        let upward = -dot(sample.user_acceleration.value, gravity) * 9.80665

        guard let home else {
            guard rate < 0.35, norm(sample.user_acceleration.value) < 0.065 else {
                quietSince = nil; quietGravity = nil; return nil
            }
            if let reference = quietGravity, angle(reference, gravity) < 0.12 {
                bias += (upward - bias) * min(1, dt / 0.25)
                if sample.t - (quietSince ?? sample.t) >= 0.5 {
                    self.home = gravity; velocity = 0; acceleration = 0
                }
            } else {
                quietGravity = gravity; quietSince = sample.t; bias = upward
            }
            return nil
        }

        guard rate <= 6 else { clearPhase(); return nil }
        acceleration += (upward - bias - acceleration) * min(1, dt / 0.08)
        velocity = velocity * exp(-dt / 5) + acceleration * dt

        switch phase {
        case .ready:
            if abs(acceleration) < 0.18, rate < 0.25, abs(velocity) < 0.06 {
                velocity *= exp(-dt / 0.1)
                bias += (upward - bias) * min(1, dt / 3)
            }
            if velocity < -0.07 {
                phase = .returning; returnTravel = 0; startedAt = sample.t
                followingCompletion = false; nextStart = nil
            } else if velocity > 0.07 {
                phase = .lifting; startedAt = nextStart ?? sample.t; travel = 0; nextStart = nil
                peakTravel = 0; peakSpeed = velocity; peakAngle = angle(home, gravity); topSince = nil
            }
        case .lifting:
            travel += velocity * dt
            peakTravel = max(peakTravel, travel)
            peakSpeed = max(peakSpeed, velocity)
            peakAngle = max(peakAngle, angle(home, gravity))
            guard sample.t - startedAt <= 8, abs(travel) <= 2 else { clearPhase(); return nil }
            let curlRange = exercise != .bicepCurl || peakAngle >= 0.8
            let qualified = peakTravel >= minimumTravel && peakSpeed >= 0.10 &&
                sample.t - startedAt >= minimumLiftTime && curlRange
            let atTop = velocity <= 0.035 && (velocity < -0.035 || (abs(acceleration) < 0.8 && rate < 1.2))
            if qualified && atTop {
                if topSince == nil { topSince = sample.t }
                if sample.t - topSince! >= 0.10 {
                    let cycle = UpperBodyCycle(start: startedAt, end: sample.t)
                    phase = .returning; returnTravel = 0; startedAt = sample.t; topSince = nil
                    followingCompletion = true; nextStart = nil
                    if let last = cycles.last, cycle.end - last.end < 0.5 { return nil }
                    cycles.append(cycle)
                    return cycle
                }
            } else { topSince = nil }
            // An incomplete lift is never turned into a repetition on lowering.
            if velocity < -0.08 && !qualified {
                phase = .returning; returnTravel = 0; startedAt = sample.t
                followingCompletion = false; nextStart = nil
            }
        case .returning:
            // Retain a measured lowering start for the next complete cycle,
            // excluding a rest held at the top and any initial setup movement.
            if followingCompletion && nextStart == nil && velocity < -0.07 { nextStart = sample.t }
            returnTravel += max(0, -velocity) * dt
            if returnTravel >= minimumTravel * 0.65 && velocity >= -0.025 {
                phase = .ready; self.home = gravity; velocity = 0; acceleration = 0
            } else if sample.t - startedAt > 8 {
                clearPhase()
            }
        }
        return nil
    }
}
