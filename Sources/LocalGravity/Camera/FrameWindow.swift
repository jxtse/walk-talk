import Foundation

public final class FrameWindow {
    private let retention: TimeInterval
    private var frames: [PreviewFrame] = []
    private let lock = NSLock()
    public init(retention: TimeInterval = 5 * 60) { self.retention = retention }

    public func append(_ f: PreviewFrame) {
        lock.lock(); defer { lock.unlock() }
        frames.append(f)
        let cutoff = Date().addingTimeInterval(-retention)
        frames.removeAll { $0.capturedAt < cutoff }
    }

    /// Most recent frame at or before `t` (default = now).
    public func latest(at t: Date = Date()) -> PreviewFrame? {
        lock.lock(); defer { lock.unlock() }
        return frames.last(where: { $0.capturedAt <= t })
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return frames.count }
    public func clear() { lock.lock(); defer { lock.unlock() }; frames.removeAll() }
}
