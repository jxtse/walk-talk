// Tests/LocalGravityTests/Keepsake/MaterialCollectorTests.swift
//
// P4-T1 step 5 — verifies KeepsakeMaterials.distanceMeters.

import XCTest
import CoreLocation
@testable import LocalGravity

final class MaterialCollectorTests: XCTestCase {
    func test_distanceMeters_sumsHaversine() {
        let now = Date()
        let mats = KeepsakeMaterials(
            track: [
                TrackPoint(coordinate: .init(latitude: 32.07, longitude: 118.79),
                           timestamp: now, horizontalAccuracy: 5),
                TrackPoint(coordinate: .init(latitude: 32.08, longitude: 118.80),
                           timestamp: now.addingTimeInterval(60),
                           horizontalAccuracy: 5)
            ],
            moments: [], dialog: [], videoURL: nil,
            startedAt: now, endedAt: now.addingTimeInterval(60)
        )
        XCTAssertGreaterThan(mats.distanceMeters, 1000)  // ~1.4 km
    }

    func test_emptyTrack_zeroDistance() {
        let now = Date()
        let mats = KeepsakeMaterials(track: [], moments: [], dialog: [],
                                     videoURL: nil,
                                     startedAt: now, endedAt: now)
        XCTAssertEqual(mats.distanceMeters, 0)
    }

    func test_collectorWiresInputsThrough() {
        let now = Date()
        let mats = MaterialCollector().collect(
            track: [],
            moments: [],
            dialog: [DialogTurn(speaker: .user, text: "hi", timestamp: now)],
            videoURL: URL(fileURLWithPath: "/tmp/x.mp4"),
            startedAt: now,
            endedAt: now.addingTimeInterval(900)
        )
        XCTAssertEqual(mats.dialog.count, 1)
        XCTAssertEqual(mats.videoURL?.lastPathComponent, "x.mp4")
        XCTAssertEqual(mats.durationSeconds, 900, accuracy: 0.001)
    }
}
