// Tests/LocalGravityTests/Keepsake/ScriptGeneratorTests.swift
//
// P4-T3 step 2 — verify the generator parses a well-formed response and
// rejects garbage. Uses an in-memory ScriptChatting stub so the tests do
// not depend on the as-yet-unmerged P1 LLMClient/StubURLProtocol.

import XCTest
@testable import LocalGravity

private final class StubScriptChat: ScriptChatting {
    let response: String
    private(set) var lastSystem: String = ""
    private(set) var lastUser: String = ""
    private(set) var lastTemperature: Double = 0
    init(response: String) { self.response = response }
    func scriptChat(model: String,
                    systemPrompt: String,
                    userMessage: String,
                    temperature: Double) async throws -> String {
        lastSystem = systemPrompt
        lastUser = userMessage
        lastTemperature = temperature
        return response
    }
}

final class ScriptGeneratorTests: XCTestCase {

    func test_parsesValidScript() async throws {
        let raw = """
        {"title":"湖边的下午","narration":"风从水面拂过","poster_prompt":"watercolor lake afternoon","video_clips":[{"start_sec":10,"duration_sec":4,"caption":"樱花"}],"bgm_tag":"calm","highlight_moment_ids":[0]}
        """
        let chat = StubScriptChat(response: raw)
        let now = Date()
        let mats = KeepsakeMaterials(track: [], moments: [], dialog: [], videoURL: nil,
                                     startedAt: now, endedAt: now.addingTimeInterval(1800))
        let script = try await ScriptGenerator(client: chat, model: "m").generate(mats)
        XCTAssertEqual(script.title, "湖边的下午")
        XCTAssertEqual(script.videoClips.first?.caption, "樱花")
        XCTAssertEqual(script.bgmTag, "calm")
        XCTAssertEqual(script.highlightMomentIds, [0])
    }

    func test_throwsOnGarbage() async {
        let chat = StubScriptChat(response: "not json at all")
        let now = Date()
        let mats = KeepsakeMaterials(track: [], moments: [], dialog: [], videoURL: nil,
                                     startedAt: now, endedAt: now)
        do {
            _ = try await ScriptGenerator(client: chat, model: "m").generate(mats)
            XCTFail("expected throw")
        } catch ScriptGeneratorError.parse {
            // ok
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_extractJSON_stripsCodeFenceProse() {
        let messy = """
        Sure! Here you go:
        ```json
        {"a":1}
        ```
        """
        XCTAssertEqual(ScriptGenerator.extractJSON(from: messy), "{\"a\":1}")
    }

    func test_summary_includesDistanceAndMomentLines() {
        let now = Date()
        let mats = KeepsakeMaterials(
            track: [],
            moments: [Moment(kind: .idea, context: "blossom", coordinate: nil, timestamp: now)],
            dialog: [DialogTurn(speaker: .user, text: "hello", timestamp: now)],
            videoURL: nil, startedAt: now, endedAt: now.addingTimeInterval(60)
        )
        let s = ScriptGenerator.summarize(mats)
        XCTAssertTrue(s.contains("blossom"))
        XCTAssertTrue(s.contains("user: hello"))
    }
}
