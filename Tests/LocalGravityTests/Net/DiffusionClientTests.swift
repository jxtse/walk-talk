// Tests/LocalGravityTests/Net/DiffusionClientTests.swift
//
// P4-T4 step 2 — verify base64 decoding using a tiny known-good 1×1 PNG.

import XCTest
@testable import LocalGravity

#if canImport(UIKit)
/// URLProtocol stub local to this file to avoid clashing with P1's
/// canonical StubURLProtocol or P2's StubURLProtocolP2.
final class StubURLProtocolP4Diffusion: URLProtocol {
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

final class DiffusionClientTests: XCTestCase {
    /// 1×1 black PNG — known-good base64.
    static let blackPixelB64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkAAIAAAoAAv/lxKUAAAAASUVORK5CYII="

    private func makeSession(responder: @escaping (URLRequest) -> (HTTPURLResponse, Data)) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocolP4Diffusion.self]
        StubURLProtocolP4Diffusion.responder = responder
        return URLSession(configuration: cfg)
    }

    func test_decodesB64Image() async throws {
        let json = "{\"data\":[{\"b64_json\":\"\(Self.blackPixelB64)\"}]}"
        let session = makeSession { req in
            let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r, json.data(using: .utf8)!)
        }
        let client = DiffusionClient(endpoint: URL(string: "http://stub")!,
                                     apiKey: "k", model: "m", session: session)
        let img = try await client.generate(prompt: "x")
        XCTAssertEqual(img.size, CGSize(width: 1, height: 1))
    }

    func test_throwsOn500() async {
        let session = makeSession { req in
            let r = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (r, "boom".data(using: .utf8)!)
        }
        let client = DiffusionClient(endpoint: URL(string: "http://stub")!,
                                     apiKey: "k", model: "m", session: session)
        do {
            _ = try await client.generate(prompt: "x")
            XCTFail("expected throw")
        } catch DiffusionError.http(let code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_throwsOnUnknownPayload() async {
        let session = makeSession { req in
            let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r, "{}".data(using: .utf8)!)
        }
        let client = DiffusionClient(endpoint: URL(string: "http://stub")!,
                                     apiKey: "k", model: "m", session: session)
        do {
            _ = try await client.generate(prompt: "x")
            XCTFail()
        } catch DiffusionError.decoding {
            // ok
        } catch {
            XCTFail("\(error)")
        }
    }
}
#endif
