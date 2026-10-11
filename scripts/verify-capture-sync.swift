import Foundation

@main
struct VerifyCaptureSync {
    static func main() throws {
        // Asymmetric clocks with symmetric 80ms transport and 30ms watch processing.
        let clock = CaptureClockReading(phoneSent: 100, watchReceived: 105.08, watchSent: 105.11, phoneReceived: 100.19)
        precondition(abs(clock.offset - 5) < 0.000001)
        precondition(abs(clock.roundTrip - 0.16) < 0.000001)
        let id = UUID()
        var item = VideoCaptureManifest(id: id, exercise: "squat", createdAt: Date(), videoStartedAt: 100, watchClockOffset: clock.offset, clockRoundTrip: clock.roundTrip)
        precondition(item.sensorOffsetInVideo == nil)
        item.sampleOriginOnPhone = 105.3 - clock.offset
        precondition(abs(item.sensorOffsetInVideo! - 0.3) < 0.000001)
        item.referenceEvents = [2, 4, 6]
        item.alignmentCorrection = -0.05
        precondition(abs(item.sensorOffsetInVideo! - 0.25) < 0.000001)
        let restored = try JSONDecoder().decode(VideoCaptureManifest.self, from: JSONEncoder().encode(item))
        precondition(restored.id == id && restored.referenceEvents == [2, 4, 6])
        precondition(restored.actualCount == nil && !restored.sensorComplete && !restored.videoComplete)
        let queued = CaptureClockReading(phoneSent: 100, watchReceived: 110, watchSent: 111, phoneReceived: 109)
        precondition(queued.roundTrip >= 1) // rejected by the live handshake
        print("PASS: clock offset, processing delay, sensor/video alignment, absent timestamps, annotation persistence, latency rejection")
    }
}
