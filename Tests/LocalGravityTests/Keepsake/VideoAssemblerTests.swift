//
//  VideoAssemblerTests.swift
//  LocalGravityTests / Keepsake
//
//  P5-T5 verification (Mac-only).
//

#if canImport(AVFoundation) && canImport(UIKit)
import XCTest
import AVFoundation
import UIKit
@testable import LocalGravity

final class VideoAssemblerTests: XCTestCase {

    private var fixtureURL: URL? {
        Bundle.module.url(forResource: "fixture_360_30s", withExtension: "mp4")
            ?? Bundle(for: Self.self).url(forResource: "fixture_360_30s", withExtension: "mp4")
    }

    /// Make a tiny PNG poster on disk so the assembler has something to
    /// freeze for the outro segment.
    private func makePosterPNG() throws -> URL {
        let size = CGSize(width: 540, height: 960)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poster_\(UUID().uuidString).png")
        try img.pngData()!.write(to: url)
        return url
    }

    func test_assemble_producesMP4WithExpectedDuration() async throws {
        guard let videoURL = fixtureURL else {
            throw XCTSkip("fixture_360_30s.mp4 not present")
        }

        let materials = KeepsakeMaterials(
            gpsTrack: TestFixtures.xuanwuLakeShortTrack,
            videoFile: videoURL,
            momentImages: [],
            dialogTranscript: ""
        )
        let script = KeepsakeScript(
            videoClips: [
                KeepsakeScript.Clip(start: 5, duration: 4, caption: "湖边")
            ],
            posterText: nil
        )
        let posterURL = try makePosterPNG()

        let asm = VideoAssembler()
        let url = try await asm.assemble(materials: materials,
                                         posterURL: posterURL,
                                         script: script)
        let dur = try await AVURLAsset(url: url).load(.duration)
        // intro 4s + clip 4s + outro 2s = 10s
        XCTAssertEqual(CMTimeGetSeconds(dur), 10.0, accuracy: 0.5)
    }

    func test_assemble_throwsWhenNoVideoFile() async throws {
        let materials = KeepsakeMaterials(
            gpsTrack: [],
            videoFile: nil,
            momentImages: [],
            dialogTranscript: ""
        )
        let script = KeepsakeScript(
            videoClips: [KeepsakeScript.Clip(start: 0, duration: 1, caption: "x")],
            posterText: nil
        )
        let posterURL = try makePosterPNG()
        do {
            _ = try await VideoAssembler().assemble(materials: materials,
                                                    posterURL: posterURL,
                                                    script: script)
            XCTFail("expected throw")
        } catch let KeepsakeError.assemblyFailed(msg) {
            XCTAssertTrue(msg.contains("no recorded video"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_assemble_throwsWhenNoClipsInScript() async throws {
        guard let videoURL = fixtureURL else {
            throw XCTSkip("fixture_360_30s.mp4 not present")
        }
        let materials = KeepsakeMaterials(
            gpsTrack: TestFixtures.xuanwuLakeShortTrack,
            videoFile: videoURL,
            momentImages: [],
            dialogTranscript: ""
        )
        let script = KeepsakeScript(videoClips: [], posterText: nil)
        let posterURL = try makePosterPNG()
        do {
            _ = try await VideoAssembler().assemble(materials: materials,
                                                    posterURL: posterURL,
                                                    script: script)
            XCTFail("expected throw")
        } catch let KeepsakeError.assemblyFailed(msg) {
            XCTAssertTrue(msg.contains("no video clips"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
#endif
