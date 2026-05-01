//
//  BGMMixerTests.swift
//  LocalGravityTests / Keepsake
//
//  P5-T4 verification (Mac-only).
//

#if canImport(AVFoundation)
import XCTest
import AVFoundation
@testable import LocalGravity

final class BGMMixerTests: XCTestCase {

    private var fixtureURL: URL? {
        Bundle.module.url(forResource: "fixture_360_30s", withExtension: "mp4")
            ?? Bundle(for: Self.self).url(forResource: "fixture_360_30s", withExtension: "mp4")
    }

    func test_mix_addsAudioTrack() async throws {
        guard let videoURL = fixtureURL else {
            throw XCTSkip("fixture_360_30s.mp4 not present")
        }
        // Skip if BGM hasn't been dropped in yet (placeholder phase).
        let hasBGM = (Bundle.module.url(forResource: "walk_default",
                                        withExtension: "m4a",
                                        subdirectory: "BGM")
                      ?? Bundle.module.url(forResource: "walk_default",
                                           withExtension: "m4a")) != nil
        guard hasBGM else {
            throw XCTSkip("walk_default.m4a not present — see Sources/LocalGravity/Resources/BGM/walk_default.m4a.PLACEHOLDER.md")
        }

        let comp = AVMutableComposition()
        let videoSrc = AVURLAsset(url: videoURL)
        let videoTrack = comp.addMutableTrack(withMediaType: .video,
                                              preferredTrackID: kCMPersistentTrackID_Invalid)!
        let dur = try await videoSrc.load(.duration)
        let srcVideoTrack = try await videoSrc.loadTracks(withMediaType: .video).first!
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur),
                                       of: srcVideoTrack,
                                       at: .zero)

        try await BGMMixer().mix(into: comp, bgmName: "walk_default")
        XCTAssertEqual(comp.tracks(withMediaType: .audio).count, 1)
        XCTAssertEqual(CMTimeGetSeconds(comp.duration), CMTimeGetSeconds(dur), accuracy: 0.05)
    }

    func test_mix_missingBGM_throwsBgmNotFound() async {
        let comp = AVMutableComposition()
        // Add a tiny silent video track so duration > 0; if no fixture
        // we just rely on duration == 0 path which still fails on lookup.
        do {
            try await BGMMixer().mix(into: comp,
                                     bgmName: "absolutely_missing_track_\(UUID().uuidString)")
            XCTFail("expected throw")
        } catch BGMMixer.MixError.bgmNotFound {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
#endif
