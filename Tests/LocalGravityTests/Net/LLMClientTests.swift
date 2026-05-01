// Tests/LocalGravityTests/Net/LLMClientTests.swift
import XCTest
@testable import LocalGravity

final class LLMClientTests: XCTestCase {
    private func makeClient(_ json: String, status: Int = 200) -> LLMClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (resp, json.data(using: .utf8)!)
        }
        return LLMClient(endpoint: URL(string: "http://stub.example/v1")!,
                         apiKey: "stub",
                         session: URLSession(configuration: cfg))
    }

    func test_chat_decodesAssistantMessage() async throws {
        let client = makeClient(#"{"choices":[{"message":{"role":"assistant","content":"hi"}}]}"#)
        let resp = try await client.chat(ChatRequest(
            model: "test", messages: [ChatMessage(role: "user", content: "ping")]
        ))
        XCTAssertEqual(resp.choices.first?.message.content, "hi")
    }

    func test_chat_throwsOnHttpError() async {
        let client = makeClient("boom", status: 500)
        do {
            _ = try await client.chat(ChatRequest(model: "m", messages: []))
            XCTFail("should have thrown")
        } catch LLMClientError.http(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_default_endpoint_matchesSpec() {
        XCTAssertEqual(Secrets.defaultLLMEndpoint.absoluteString, "http://100.99.139.20:18141")
    }
}
