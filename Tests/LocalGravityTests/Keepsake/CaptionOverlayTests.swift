//
//  CaptionOverlayTests.swift
//  LocalGravityTests / Keepsake
//
//  P5-T3 verification (Mac-only).
//

#if canImport(AVFoundation) && canImport(UIKit)
import XCTest
import AVFoundation
@testable import LocalGravity

final class CaptionOverlayTests: XCTestCase {

    private var fixtureURL: URL? {
        Bundle.module.url(forResource: "fixture_360_30s", withExtension: "mp4")
            ?? Bundle(for: Self.self).url(forResource: "fixture_360_30s", withExtension: "mp4")
    }

    func test_buildComposition_returnsInstructionWithCaption() async throws {
        guard let url = fixtureURL else {
            throw XCTSkip("fixture_360_30s.mp4 not present — see Tests/LocalGravityTests/Fixtures/README.md")
        }
        let asset = AVURLAsset(url: url)
        let captions = [CaptionEntry(text: "湖边", start: 0, duration: 2)]
        let overlay = CaptionOverlay()
        let comp = try await overlay.build(for: asset,
                                           size: CGSize(width: 1080, height: 1920),
                                           captions: captions)
        XCTAssertEqual(comp.instructions.count, 1)
        XCTAssertNotNil(comp.animationTool)
        XCTAssertEqual(comp.renderSize, CGSize(width: 1080, height: 1920))
    }

    func test_buildComposition_zeroCaptions_stillProducesInstruction() async throws {
        guard let url = fixtureURL else {
            throw XCTSkip("fixture_360_30s.mp4 not present")
        }
        let asset = AVURLAsset(url: url)
        let comp = try await CaptionOverlay().build(
            for: asset,
            size: CGSize(width: 540, height: 960),
            captions: []
        )
        XCTAssertEqual(comp.instructions.count, 1)
    }
}
#endif
