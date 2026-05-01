// Sources/LocalGravity/Location/TrackBuffer.swift
//
// Rolling 30-minute GPS buffer. Pure logic, fully testable.
// Plan reference: P1-T5.
import Foundation
import CoreLocation

public struct TrackPoint: Equatable {
    public let coordinate: CLLocationCoordinate2D
    public let timestamp: Date
    public let horizontalAccuracy: Double

    public init(coordinate: CLLocationCoordinate2D, timestamp: Date, horizontalAccuracy: Double) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

/// Holds a rolling 30-minute buffer of GPS points. Thread-safe via a serial queue.
public final class TrackBuffer {
    private let retention: TimeInterval
    private var points: [TrackPoint] = []
    private let queue = DispatchQueue(label: "TrackBuffer")

    public init(retention: TimeInterval = 30 * 60) {
        self.retention = retention
    }

    public func append(_ p: TrackPoint, now: Date = Date()) {
        queue.sync {
            points.append(p)
            let cutoff = now.addingTimeInterval(-retention)
            points.removeAll { $0.timestamp < cutoff }
        }
    }

    public var count: Int { queue.sync { points.count } }
    public var snapshot: [TrackPoint] { queue.sync { points } }

    /// Returns the GPS reading closest to the given timestamp (within tolerance), or nil.
    public func nearest(to t: Date, tolerance: TimeInterval = 5) -> TrackPoint? {
        queue.sync {
            points.min(by: { abs($0.timestamp.timeIntervalSince(t)) < abs($1.timestamp.timeIntervalSince(t)) })
                .flatMap { abs($0.timestamp.timeIntervalSince(t)) <= tolerance ? $0 : nil }
        }
    }

    public func clear() { queue.sync { points.removeAll() } }
}
