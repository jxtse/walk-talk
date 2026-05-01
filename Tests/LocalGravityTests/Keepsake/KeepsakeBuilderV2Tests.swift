//
//  KeepsakeBuilderV2Tests.swift
//  LocalGravityTests / Keepsake
//
//  P5-T6 verification — the HARD fallback invariant.
//
//  These tests use in-memory stubs for every collaborator (scripter,
//  diffusion, poster, video) so they run on any platform that has
//  Foundation. They do NOT need AVFoundation or the fixture mp4.
//

import XCTest
@testable import LocalGravity

final class KeepsakeBuilderV2Tests: XCTestCase {

    // MARK: - Stubs

    private struct StubScripter: KeepsakeScripting {
        enum Mode { case success, failure }
        let mode: Mode
        let clips: [KeepsakeScript.Clip]
        init(_ mode: Mode,
             clips: [KeepsakeScript.Clip] = [
                .init(start: 5, duration: 4, caption: "湖边")
             ]) {
            self.mode = mode
            self.clips = clips
        }
        func generate(_ materials: KeepsakeMaterials) async throws -> KeepsakeScript {
            switch mode {
            case .success: return KeepsakeScript(videoClips: clips, posterText: "散步")
            case .failure: throw KeepsakeError.assemblyFailed("stub scripter")
            }
        }
    }

    private struct StubDiffusion: DiffusionGenerating {
        enum Mode { case success, failure }
        let mode: Mode
        init(_ mode: Mode) { self.mode = mode }
        func generate(prompt: String) async throws -> URL {
            switch mode {
            case .success:
                return FileManager.default.temporaryDirectory
                    .appendingPathComponent("stub_diffusion.png")
            case .failure: throw KeepsakeError.assemblyFailed("stub diffusion")
            }
        }
    }

    private struct StubPoster: PosterComposing {
        let url: URL
        let shouldThrow: Bool
        init(throwing: Bool = false) {
            self.shouldThrow = throwing
            self.url = FileManager.default.temporaryDirectory
                .appendingPathComponent("stub_poster_\(UUID().uuidString).png")
            // Materialize a tiny file so any caller .path checks pass.
            FileManager.default.createFile(atPath: self.url.path,
                                           contents: Data([0x00]))
        }
        func compose(materials: KeepsakeMaterials,
                     script: KeepsakeScript) async throws -> URL {
            if shouldThrow { throw KeepsakeError.assemblyFailed("stub poster") }
            return url
        }
    }

    private struct StubVideoAssembler: VideoAssembling {
        enum Mode { case success, failure }
        let mode: Mode
        init(_ mode: Mode) { self.mode = mode }
        func assemble(materials: KeepsakeMaterials,
                      posterURL: URL,
                      script: KeepsakeScript) async throws -> URL {
            switch mode {
            case .success:
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("stub_video_\(UUID().uuidString).mp4")
                FileManager.default.createFile(atPath: url.path,
                                               contents: Data([0x00]))
                return url
            case .failure:
                throw KeepsakeError.assemblyFailed("stub video failure")
            }
        }
    }

    // MARK: - Materials

    private func materials(withVideo: Bool = true) -> KeepsakeMaterials {
        let videoURL: URL?
        if withVideo {
            let u = FileManager.default.temporaryDirectory
                .appendingPathComponent("stub_recording_\(UUID().uuidString).mp4")
            FileManager.default.createFile(atPath: u.path, contents: Data([0x00]))
            videoURL = u
        } else {
            videoURL = nil
        }
        return KeepsakeMaterials(
            gpsTrack: TestFixtures.xuanwuLakeShortTrack,
            videoFile: videoURL,
            momentImages: [],
            dialogTranscript: "stub"
        )
    }

    // MARK: - Tests

    func test_build_returnsVideo_whenAssemblySucceeds() async throws {
        let builder = KeepsakeBuilder(
            scripter: StubScripter(.success),
            diffusion: StubDiffusion(.success),
            poster: StubPoster(),
            video: StubVideoAssembler(.success)
        )
        let result = try await builder.build(materials: materials())
        XCTAssertEqual(result.kind, .video)
    }

    func test_build_fallsBackToPoster_whenVideoFails() async throws {
        let builder = KeepsakeBuilder(
            scripter: StubScripter(.success),
            diffusion: StubDiffusion(.success),
            poster: StubPoster(),
            video: StubVideoAssembler(.failure)
        )
        let result = try await builder.build(materials: materials())
        XCTAssertEqual(result.kind, .poster)
    }

    func test_build_fallsBackToPoster_whenNoVideoFile() async throws {
        let builder = KeepsakeBuilder(
            scripter: StubScripter(.success),
            diffusion: StubDiffusion(.success),
            poster: StubPoster(),
            video: StubVideoAssembler(.success) // would succeed if invoked
        )
        let result = try await builder.build(materials: materials(withVideo: false))
        XCTAssertEqual(result.kind, .poster, "no video file → must skip V2 path")
    }

    func test_build_fallsBackToPoster_whenScriptHasNoClips() async throws {
        let builder = KeepsakeBuilder(
            scripter: StubScripter(.success, clips: []),
            diffusion: StubDiffusion(.success),
            poster: StubPoster(),
            video: StubVideoAssembler(.success)
        )
        let result = try await builder.build(materials: materials())
        XCTAssertEqual(result.kind, .poster, "empty script clips → must skip V2 path")
    }

    func test_build_failsafeScript_whenScripterThrows_andStillReturnsPoster() async throws {
        let builder = KeepsakeBuilder(
            scripter: StubScripter(.failure),
            diffusion: StubDiffusion(.success),
            poster: StubPoster(),
            video: StubVideoAssembler(.success) // should not be invoked: failsafe has no clips
        )
        let result = try await builder.build(materials: materials())
        XCTAssertEqual(result.kind, .poster, "failsafe script has no clips → poster only")
    }

    func test_build_propagatesPosterFailure() async {
        // P4 close-out invariant: if the poster path itself fails, we
        // surface the error instead of returning a video — the contract
        // is a poster floor, not "any url at all".
        let builder = KeepsakeBuilder(
            scripter: StubScripter(.success),
            diffusion: StubDiffusion(.success),
            poster: StubPoster(throwing: true),
            video: StubVideoAssembler(.success)
        )
        do {
            _ = try await builder.build(materials: materials())
            XCTFail("expected throw from poster failure")
        } catch {
            // Expected — preserves P4 invariant.
        }
    }

    func test_build_posterOnlyMode_whenVideoNil() async throws {
        let builder = KeepsakeBuilder(
            scripter: StubScripter(.success),
            diffusion: StubDiffusion(.success),
            poster: StubPoster(),
            video: nil  // explicit P4-only mode
        )
        let result = try await builder.build(materials: materials())
        XCTAssertEqual(result.kind, .poster)
    }
}
