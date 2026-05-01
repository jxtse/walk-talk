//
//  ClipExtractorTests.swift
//  LocalGravityTests / Keepsake
//
//  P5-T2 verification (Mac-only — requires AVFoundation + the fixture mp4).
//
//  Fixture: see ../Fixtures/README.md for how to drop in
//  `fixture_360_30s.mp4`. Tests are no-ops if the fixture is absent so a
//  CI run on a clean checkout still passes the rest of the suite.
//

#if canImport(AVFoundation)
import XCTest
import AVFoundation
@testable import LocalGravity

final class ClipExtractorTests: XCTestCase {

    private var fixtureURL: URL? {
        Bundle.module.url(forResource: "fixture_360_30s", withExtension: "mp4")
            ?? Bundle(for: Self.self).url(forResource: "fixture_360_30s", withExtension: "mp4")
    }

    func test_extract_producesClipOfExactDuration() async throws {
        guard let src = fixtureURL else {
            throw XCTSkip("fixture_360_30s.mp4 not present — see Tests/LocalGravityTests/Fixtures/README.md")
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).mp4")
        let extractor = ClipExtractor()
        try await extractor.extract(
            from: src,
            range: CMTimeRange(
                start: CMTime(seconds: 5, preferredTimescale: 600),
                duration: CMTime(seconds: 4, preferredTimescale: 600)
            ),
            output: out
        )
        let dur = try await AVURLAsset(url: out).load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(dur), 4.0, accuracy: 0.1)
    }

    func test_extract_invalidSource_throwsAssemblyFailed() async {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("does_not_exist_\(UUID().uuidString).mp4")
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).mp4")
        let extractor = ClipExtractor()
        do {
            try await extractor.extract(
                from: bogus,
                range: CMTimeRange(start: .zero,
                                   duration: CMTime(seconds: 1, preferredTimescale: 600)),
                output: out
            )
            XCTFail("expected throw")
        } catch let KeepsakeError.assemblyFailed(msg) {
            XCTAssertTrue(msg.contains("clip extract"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
#endif
