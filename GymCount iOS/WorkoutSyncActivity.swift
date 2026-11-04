import Foundation

@MainActor
final class WorkoutSyncActivity {
    private let interval: Duration
    private var lastRequest: ContinuousClock.Instant?
    private var timeoutTask: Task<Void, Never>?

    init(interval: Duration = .seconds(20)) { self.interval = interval }

    func beginRequest(force: Bool) -> Bool {
        let now = ContinuousClock.now
        if !force, let lastRequest, lastRequest.duration(to: now) < interval { return false }
        lastRequest = now
        return true
    }

    func restartTimeout(_ action: @escaping @MainActor () -> Void) {
        cancelTimeout()
        let interval = interval
        timeoutTask = Task { @MainActor in
            do { try await Task.sleep(for: interval) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    deinit { timeoutTask?.cancel() }
}
