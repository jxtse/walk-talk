// Tests/LocalGravityTests/Keepsake/KeepsakeBuilderTests.swift
//
// P4-T6 step 4 — verify the failsafe invariant: even when the LLM throws
// AND diffusion throws, KeepsakeBuilder must still return a non-trivial
// PNG file on disk.

import XCTest
@testable import LocalGravity

#if canImport(UIKit)
import UIKit

private final class FailingChat: ScriptChatting {
    func scriptChat(model: String, systemPrompt: String,
                    userMessage: String, temperature: Double) async throws -> String {
        throw NSError(domain: "stub", code: -1)
    }
}

/// Diffusion stub that always 500s — same shape as the real client but
/// guaranteed to fail.
private func failingDiffusion() -> DiffusionClient {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubURLProtocolP4Diffusion.self]
    StubURLProtocolP4Diffusion.responder = { req in
        let r = HTTPURLResponse(url: req.url!, statusCode: 500,
                                httpVersion: nil, headerFields: nil)!
        return (r, "boom".data(using: .utf8)!)
    }
    return DiffusionClient(endpoint: URL(string: "http://stub")!,
                           apiKey: "k", model: "m",
                           session: URLSession(configuration: cfg))
}

final class KeepsakeBuilderTests: XCTestCase {

    func test_builderProducesPoster_whenEverythingFails() async throws {
        let scripter = ScriptGenerator(client: FailingChat(), model: "m")
        let builder = KeepsakeBuilder(scripter: scripter,
                                      diffusion: failingDiffusion())
        let now = Date()
        let mats = KeepsakeMaterials(track: [], moments: [], dialog: [],
                                     videoURL: nil,
                                     startedAt: now,
                                     endedAt: now.addingTimeInterval(900))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = try await builder.buildPoster(materials: mats, outputDir: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 1000) // non-trivial PNG
    }

    func test_failsafeScript_isStableEnoughToCompose() {
        let now = Date()
        let mats = KeepsakeMaterials(track: [], moments: [], dialog: [],
                                     videoURL: nil,
                                     startedAt: now, endedAt: now)
        let s = KeepsakeBuilder.failsafeScript(mats)
        XCTAssertFalse(s.title.isEmpty)
        XCTAssertFalse(s.narration.isEmpty)
        XCTAssertFalse(s.posterPrompt.isEmpty)
        XCTAssertEqual(s.videoClips.count, 0)
    }
}
#endif
