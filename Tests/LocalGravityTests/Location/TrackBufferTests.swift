// Tests/LocalGravityTests/Location/TrackBufferTests.swift
import XCTest
import CoreLocation
@testable import LocalGravity

final class TrackBufferTests: XCTestCase {
    private func p(_ lat: Double, _ lng: Double, _ t: Date) -> TrackPoint {
        TrackPoint(coordinate: .init(latitude: lat, longitude: lng), timestamp: t, horizontalAccuracy: 5)
    }

    func test_append_storesPoints() {
        let buf = TrackBuffer()
        buf.append(p(0, 0, Date()))
        XCTAssertEqual(buf.count, 1)
    }

    func test_evictsOlderThanRetention() {
        let buf = TrackBuffer(retention: 60)
        let now = Date()
        buf.append(p(0, 0, now.addingTimeInterval(-120)), now: now)
        buf.append(p(1, 1, now), now: now)
        XCTAssertEqual(buf.count, 1)
        XCTAssertEqual(buf.snapshot.first?.coordinate.latitude, 1)
    }

    func test_nearest_returnsClosestWithinTolerance() {
        let buf = TrackBuffer()
        let base = Date()
        buf.append(p(0, 0, base))
        buf.append(p(1, 1, base.addingTimeInterval(10)))
        let hit = buf.nearest(to: base.addingTimeInterval(2), tolerance: 5)
        XCTAssertEqual(hit?.coordinate.latitude, 0)
    }

    func test_nearest_nilWhenOutsideTolerance() {
        let buf = TrackBuffer()
        let base = Date()
        buf.append(p(0, 0, base))
        XCTAssertNil(buf.nearest(to: base.addingTimeInterval(60), tolerance: 5))
    }

    func test_clear_removesAllPoints() {
        let buf = TrackBuffer()
        buf.append(p(0, 0, Date()))
        buf.append(p(1, 1, Date()))
        buf.clear()
        XCTAssertEqual(buf.count, 0)
    }
}
