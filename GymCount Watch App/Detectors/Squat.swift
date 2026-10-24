import Foundation
import CoreMotion
import Combine

final class SquatDetector: ObservableObject {
    private let stream = SquatStream()
    @Published private(set) var repCount = 0
    @Published private(set) var lastRepTime: Date?
    var onRepDetected: ((Double) -> Void)?

    func processMotion(_ data: CMDeviceMotion) {
        let sample = BenchMotionSample(t: data.timestamp,
            gravity: BenchVector(x: data.gravity.x, y: data.gravity.y, z: data.gravity.z),
            user_acceleration: BenchVector(x: data.userAcceleration.x, y: data.userAcceleration.y, z: data.userAcceleration.z),
            rotation_rate: BenchVector(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z))
        guard let cycle = stream.append(sample) else { return }
        repCount += 1
        let anchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        lastRepTime = Date(timeIntervalSince1970: anchor + cycle.end)
        onRepDetected?(cycle.end)
    }
    func markInterrupted() { stream.reset() }
    func resetCount() { stream.reset(); repCount = 0; lastRepTime = nil }
}
