// Tests/LocalGravityTests/Map/MapRendererTests.swift
//
// P4-T2 step 3 — pure-logic tests for the keepsake snapshot helpers.

import XCTest
import CoreLocation
@testable import LocalGravity

#if canImport(UIKit)
final class MapRendererTests: XCTestCase {
    func test_center_averages() {
        let c = MapRenderer.center(of: [
            .init(latitude: 0, longitude: 0),
            .init(latitude: 2, longitude: 4)
        ])
        XCTAssertEqual(c.latitude, 1, accuracy: 0.0001)
        XCTAssertEqual(c.longitude, 2, accuracy: 0.0001)
    }

    func test_center_emptyTrackIsZeroZero() {
        let c = MapRenderer.center(of: [])
        XCTAssertEqual(c.latitude, 0)
        XCTAssertEqual(c.longitude, 0)
    }

    func test_zoom_smallSpan_isHigh() {
        let z = MapRenderer.zoomLevel(for: [
            .init(latitude: 32.072, longitude: 118.794),
            .init(latitude: 32.073, longitude: 118.795)
        ])
        XCTAssertEqual(z, 17)
    }

    func test_zoom_largeSpan_isLow() {
        let z = MapRenderer.zoomLevel(for: [
            .init(latitude: 30, longitude: 110),
            .init(latitude: 35, longitude: 120)
        ])
        XCTAssertEqual(z, 9)
    }

    func test_renderStaticSnapshot_producesImageOfRequestedSize() async {
        let img = await MapRenderer.renderStaticSnapshot(
            track: [
                .init(latitude: 32.072, longitude: 118.794),
                .init(latitude: 32.073, longitude: 118.795)
            ],
            size: CGSize(width: 200, height: 120)
        )
        XCTAssertEqual(img.size, CGSize(width: 200, height: 120))
    }

    func test_renderStaticSnapshot_emptyTrackStillReturnsImage() async {
        let img = await MapRenderer.renderStaticSnapshot(
            track: [],
            size: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(img.size, CGSize(width: 100, height: 100))
    }
}
#endif
