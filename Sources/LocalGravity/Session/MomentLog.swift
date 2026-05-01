import Foundation
import CoreLocation

public struct Moment: Equatable {
    public enum Kind: String, Codable { case idea, place, vibe }
    public let kind: Kind
    public let context: String
    public let coordinate: CLLocationCoordinate2D?
    public let timestamp: Date

    public init(kind: Kind, context: String, coordinate: CLLocationCoordinate2D?, timestamp: Date) {
        self.kind = kind
        self.context = context
        self.coordinate = coordinate
        self.timestamp = timestamp
    }
}

public final class MomentLog {
    private(set) public var moments: [Moment] = []
    private let lock = NSLock()
    public init() {}
    public func add(_ m: Moment) { lock.lock(); defer { lock.unlock() }; moments.append(m) }
    public func snapshot() -> [Moment] { lock.lock(); defer { lock.unlock() }; return moments }
    public func clear() { lock.lock(); defer { lock.unlock() }; moments.removeAll() }
}
