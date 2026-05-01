// Tests/LocalGravityTests/Net/StubURLProtocol.swift
//
// Reusable URLProtocol stub for unit tests. Shared by LLMClientTests and
// AmapClientTests.
import Foundation

final class StubURLProtocol: URLProtocol {
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
