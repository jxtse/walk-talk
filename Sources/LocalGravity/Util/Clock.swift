import Foundation

public protocol Clock { func now() -> Date }

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

public final class FakeClock: Clock {
    public var current: Date
    public init(_ d: Date = Date(timeIntervalSince1970: 0)) { self.current = d }
    public func now() -> Date { current }
    public func advance(by sec: TimeInterval) { current.addTimeInterval(sec) }
}
