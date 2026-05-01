import Foundation

public final class ProactiveQuota {
    private let limit: Int
    private let window: TimeInterval
    private let clock: Clock
    private var stamps: [Date] = []
    private let lock = NSLock()

    public init(limit: Int = 3, window: TimeInterval = 600, clock: Clock = SystemClock()) {
        self.limit = limit
        self.window = window
        self.clock = clock
    }

    public func canSpeak() -> Bool {
        lock.lock(); defer { lock.unlock() }
        prune()
        return stamps.count < limit
    }

    public func recordSpoken() {
        lock.lock(); defer { lock.unlock() }
        stamps.append(clock.now())
        prune()
    }

    private func prune() {
        let cutoff = clock.now().addingTimeInterval(-window)
        stamps.removeAll { $0 < cutoff }
    }
}
