import XCTest
@testable import LocalGravity

/// A LLM stand-in that returns a pre-scripted sequence of responses, ignoring inputs.
final class ScriptedLLM {
    private let scripts: [String]   // raw JSON response bodies, in order
    private let lock = NSLock()
    private var idx = 0
    init(_ scripts: [String]) { self.scripts = scripts }
    func makeClient() -> LLMClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ScriptedURLProtocol.self]
        ScriptedURLProtocol.next = { [self] in
            lock.lock(); defer { lock.unlock() }
            let body = scripts[min(idx, scripts.count - 1)]
            idx += 1
            return body
        }
        return LLMClient(endpoint: URL(string: "http://stub/v1")!, apiKey: "k",
                         session: URLSession(configuration: cfg))
    }
}

final class ScriptedURLProtocol: URLProtocol {
    static var next: (() -> String)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = (Self.next?() ?? "{}").data(using: .utf8)!
        let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private extension String {
    /// Wrap self as a JSON string literal (for embedding in another JSON document).
    var jsonEscaped: String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }
}

private func toolCallResponse(name: String, args: String, callId: String = "c1") -> String {
    """
    {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[
      {"id":"\(callId)","type":"function","function":{"name":"\(name)","arguments":\(args.jsonEscaped)}}
    ]},"finish_reason":"tool_calls"}]}
    """
}
private func finalResponse(_ text: String) -> String {
    """
    {"choices":[{"message":{"role":"assistant","content":"\(text)"},"finish_reason":"stop"}]}
    """
}

final class AgentRuntimeTests: XCTestCase {
    final class SpySpeaker: Speaker {
        var spoken: [String] = []
        func speak(_ text: String) async throws { spoken.append(text) }
    }

    // Scenario 1: passive Q&A — single tool call then finish.
    func test_agentCallsToolThenFinishes() async throws {
        let speaker = SpySpeaker()
        let scripted = ScriptedLLM([
            toolCallResponse(name: "speak_to_user", args: #"{"text":"你好"}"#),
            finalResponse("done")
        ])
        let llm = scripted.makeClient()
        let registry = ToolRegistry([SpeakToUserTool(speaker: speaker, quota: nil)])
        let agent = AgentRuntime(llm: llm, model: "m", tools: registry)
        let result = try await agent.handle(.userSpoke("hi"))
        XCTAssertEqual(speaker.spoken, ["你好"])
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.finalContent, "done")
    }

    // Scenario 2: proactive recommendation accepted — speak + quota consumed.
    func test_proactiveRecommendation_accepted_consumesQuota() async throws {
        let speaker = SpySpeaker()
        let q = ProactiveQuota(limit: 3, window: 600, clock: FakeClock())
        let scripted = ScriptedLLM([
            toolCallResponse(name: "speak_to_user",
                             args: #"{"text":"前面 200 米有家民国老茶馆"}"#),
            finalResponse("recommended")
        ])
        let registry = ToolRegistry([SpeakToUserTool(speaker: speaker, quota: q)])
        let agent = AgentRuntime(llm: scripted.makeClient(), model: "m", tools: registry)
        _ = try await agent.handle(.locationTick)
        XCTAssertEqual(speaker.spoken.count, 1)
        // limit was 3 → after 1 spoken, 2 remain
        XCTAssertTrue(q.canSpeak())
        // exhaust the rest to confirm consumption was recorded
        q.recordSpoken(); q.recordSpoken()
        XCTAssertFalse(q.canSpeak())
    }

    // Scenario 3: proactive recommendation rejected — quota still consumed
    // even though the speaker is not invoked because limit has already been hit.
    func test_quotaExceeded_doesNotInvokeSpeaker() async throws {
        let speaker = SpySpeaker()
        let q = ProactiveQuota(limit: 0, window: 600, clock: FakeClock())
        let scripted = ScriptedLLM([
            toolCallResponse(name: "speak_to_user", args: #"{"text":"hi"}"#),
            finalResponse("ok")
        ])
        let registry = ToolRegistry([SpeakToUserTool(speaker: speaker, quota: q)])
        let agent = AgentRuntime(llm: scripted.makeClient(), model: "m", tools: registry)
        _ = try await agent.handle(.locationTick)
        XCTAssertTrue(speaker.spoken.isEmpty)
    }

    // Scenario 4: passive capture — record_moment, no speech.
    func test_recordMoment_doesNotSpeak() async throws {
        let log = MomentLog()
        let buf = TrackBuffer()
        let scripted = ScriptedLLM([
            toolCallResponse(name: "record_moment",
                             args: #"{"kind":"idea","context":"研究 idea"}"#),
            finalResponse("")
        ])
        let registry = ToolRegistry([RecordMomentTool(log: log, trackBuffer: buf)])
        let agent = AgentRuntime(llm: scripted.makeClient(), model: "m", tools: registry)
        _ = try await agent.handle(.userSpoke("记一下这个想法"))
        XCTAssertEqual(log.snapshot().count, 1)
        XCTAssertEqual(log.snapshot().first?.kind, .idea)
    }

    // Scenario 5: silent default — model emits no tool calls and no content.
    func test_silentDefault_noToolsNoSpeech() async throws {
        let speaker = SpySpeaker()
        let scripted = ScriptedLLM([
            finalResponse("")
        ])
        let registry = ToolRegistry([SpeakToUserTool(speaker: speaker, quota: nil)])
        let agent = AgentRuntime(llm: scripted.makeClient(), model: "m", tools: registry)
        let result = try await agent.handle(.locationTick)
        XCTAssertTrue(speaker.spoken.isEmpty)
        XCTAssertEqual(result.toolCalls.count, 0)
        XCTAssertEqual(result.finalContent, "")
    }
}
