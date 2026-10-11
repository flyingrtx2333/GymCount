import Foundation

// Diagnostic only: preserve sensor timestamps and never fill missing samples.
struct CaptureContinuity {
    private(set) var lastTimestamp: Double?
    private(set) var maximumGap: Double = 0
    private(set) var maximumDeliveryDelay: Double = 0

    mutating func observe(timestamp: Double, received: Double) {
        if let previous = lastTimestamp {
            maximumGap = max(maximumGap, timestamp - previous)
        }
        lastTimestamp = timestamp
        maximumDeliveryDelay = max(maximumDeliveryDelay, received - timestamp)
    }

    var hasGap: Bool { maximumGap > 0.25 }
}
