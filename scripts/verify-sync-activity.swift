import Foundation

@main
enum VerifySyncActivity {
    @MainActor static func main() async throws {
        let interval = Duration.milliseconds(300)
        let activity = WorkoutSyncActivity(interval: interval)
        var automaticRequests = 0
        for _ in 0..<100 {
            if activity.beginRequest(force: false) { automaticRequests += 1 }
        }
        precondition(automaticRequests == 1, "Automatic callbacks restarted the same request")
        precondition(activity.beginRequest(force: true), "Explicit retry was blocked")
        precondition(!activity.beginRequest(force: false), "Automatic callback immediately repeated manual retry")
        try await Task.sleep(for: .milliseconds(400))
        precondition(activity.beginRequest(force: false), "Automatic reconnect remained blocked after cooldown")

        var timeouts = 0
        var prematureTimeouts = 0
        var lastProgress = ContinuousClock.now
        for _ in 0..<8 {
            lastProgress = .now
            activity.restartTimeout {
                timeouts += 1
                if lastProgress.duration(to: .now) < interval { prematureTimeouts += 1 }
            }
            try await Task.sleep(for: .milliseconds(60))
        }
        precondition(timeouts == 0, "An obsolete timeout fired during ongoing progress")
        try await Task.sleep(for: .milliseconds(400))
        precondition(timeouts == 1 && prematureTimeouts == 0, "The inactivity deadline did not fire exactly once")

        activity.restartTimeout { timeouts += 1 }
        activity.cancelTimeout()
        try await Task.sleep(for: .milliseconds(400))
        precondition(timeouts == 1, "A completed sync was changed by a cancelled timeout")

        print("PASS: actual clock/task cancellation, progress extends deadline, one inactivity timeout, completed cancellation, coalesced automatic requests, explicit retry and reconnect")
    }
}
