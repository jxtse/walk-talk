import XCTest
@testable import LocalGravity

/// URLProtocol stub re-declared here (P1 places the canonical version under
/// Tests/LocalGravityTests/LLM). To avoid a duplicate-class conflict, this
/// test stub is namespaced.
final class StubURLProtocolP2: URLProtocol {
    static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let r = Self.responder?(request) else { return }
        client?.urlProtocol(self, didReceive: r.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class LLMClientToolCallTests: XCTestCase {
    func test_parsesToolCall() async throws {
        let json = #"""
        {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[
          {"id":"c1","type":"function","function":{"name":"speak_to_user","arguments":"{\"text\":\"你好\"}"}}
        ]},"finish_reason":"tool_calls"}]}
        """#
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocolP2.self]
        StubURLProtocolP2.responder = { req in
            let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r, json.data(using: .utf8)!)
        }
        let client = LLMClient(endpoint: URL(string: "http://stub/v1")!, apiKey: "k",
                               session: URLSession(configuration: cfg))
        let resp = try await client.chatWithTools(ChatRequestWithTools(
            model: "m",
            messages: [.object(["role": .string("user"), "content": .string("hi")])],
            tools: nil
        ))
        XCTAssertEqual(resp.choices.first?.message.tool_calls?.first?.function.name, "speak_to_user")
    }
}
