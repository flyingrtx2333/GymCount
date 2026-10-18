import Foundation
import CoreMotion

final class BenchPressDetector {
    private let stream = BenchPressStream()
    var onAnalysis: ((BenchAnalysis) -> Void)?

    func processMotion(_ data: CMDeviceMotion) {
        let sample = BenchMotionSample(t: data.timestamp,
            gravity: BenchVector(x: data.gravity.x, y: data.gravity.y, z: data.gravity.z),
            user_acceleration: BenchVector(x: data.userAcceleration.x, y: data.userAcceleration.y, z: data.userAcceleration.z),
            rotation_rate: BenchVector(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z))
        if let analysis = stream.append(sample) { onAnalysis?(analysis) }
    }
    func markInterrupted() { stream.markInterrupted() }
    func finish() -> BenchAnalysis {
        if let last = stream.lastTimestamp, ProcessInfo.processInfo.systemUptime - last > 1 {
            stream.markInterrupted()
        }
        return stream.finish()
    }
    func resetCount() { stream.reset() }
}
