//
//  TrackAnimRendererTests.swift
//  LocalGravityTests / Keepsake
//
//  P5-T1 verification (deferred to Mac runtime — requires AVFoundation).
//

#if canImport(AVFoundation) && canImport(UIKit)
import XCTest
import AVFoundation
@testable import LocalGravity

final class TrackAnimRendererTests: XCTestCase {

    func test_render_producesMP4OfRequestedDuration() async throws {
        let pts: [GPSPoint] = TestFixtures.xuanwuLakeShortTrack
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("intro_\(UUID().uuidString).mp4")
        let renderer = TrackAnimRenderer()
        try await renderer.render(track: pts,
                                  size: CGSize(width: 1080, height: 1920),
                                  duration: 4.0,
                                  output: url)
        let asset = AVURLAsset(url: url)
        let dur = try await asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(dur), 4.0, accuracy: 0.2)
    }

    func test_render_emptyTrack_stillProducesValidFile() async throws {
        // The fallback invariant: even with no GPS points the intro must
        // produce *some* MP4 (black frames are fine) so the orchestrator
        // does not fail-over to the poster path purely because of an
        // empty track.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("intro_empty_\(UUID().uuidString).mp4")
        let renderer = TrackAnimRenderer()
        try await renderer.render(track: [],
                                  size: CGSize(width: 540, height: 960),
                                  duration: 1.0,
                                  output: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
#endif
