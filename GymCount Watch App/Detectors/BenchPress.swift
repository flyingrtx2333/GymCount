import Foundation
import CoreMotion

final class BenchPressDetector {
    private let stream = BenchPressStream()
    private let feedback = BenchPressFeedback()
    var onCompletion: ((BenchCycle) -> Void)?
    var onAnalysis: ((BenchAnalysis) -> Void)?

    func processMotion(_ data: CMDeviceMotion) {
        let sample = BenchMotionSample(t: data.timestamp,
            gravity: BenchVector(x: data.gravity.x, y: data.gravity.y, z: data.gravity.z),
            user_acceleration: BenchVector(x: data.userAcceleration.x, y: data.userAcceleration.y, z: data.userAcceleration.z),
            rotation_rate: BenchVector(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z))
        process(sample, receivedAt: ProcessInfo.processInfo.systemUptime)
    }

    // The same sensor/arrival-time entry is used by real recording replays.
    func process(_ sample: BenchMotionSample, receivedAt: Double) {
        let age = receivedAt - sample.t
        if age >= 0 && age <= 0.25 {
            if feedback.append(sample) != nil, let cycle = feedback.lastCycle { onCompletion?(cycle) }
        } else { feedback.reset() }
        if let analysis = stream.append(sample) { onAnalysis?(analysis) }
    }
    func markInterrupted() { stream.markInterrupted(); feedback.reset() }
    func finish(receivedAt: Double = ProcessInfo.processInfo.systemUptime) -> BenchAnalysis {
        if let last = stream.lastTimestamp, receivedAt - last > 1 {
            stream.markInterrupted()
        }
        return stream.finish()
    }
    func resetCount() { stream.reset(); feedback.reset() }
}
