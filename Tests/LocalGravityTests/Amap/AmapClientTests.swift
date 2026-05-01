// Tests/LocalGravityTests/Amap/AmapClientTests.swift
import XCTest
import CoreLocation
@testable import LocalGravity

final class AmapClientTests: XCTestCase {
    private func makeClient(json: String, status: Int = 200) -> AmapClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.responder = { req in
            let r = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (r, json.data(using: .utf8)!)
        }
        return AmapClient(key: "k", session: URLSession(configuration: cfg))
    }

    func test_aroundSearch_parsesPois() async throws {
        let client = makeClient(json: #"""
        {"status":"1","pois":[
          {"id":"abc","name":"老茶馆","type":"美食","location":"118.794,32.072","distance":"123","address":"南京市"}
        ]}
        """#)
        let result = try await client.aroundSearch(lat: 32.072, lng: 118.794)
        XCTAssertEqual(result.first?.name, "老茶馆")
        XCTAssertEqual(result.first?.distanceMeters, 123)
        XCTAssertEqual(result.first?.coordinate.latitude, 32.072)
    }

    func test_aroundSearch_throwsOnApiStatus() async {
        let client = makeClient(json: #"{"status":"0","info":"INVALID_KEY"}"#)
        do {
            _ = try await client.aroundSearch(lat: 0, lng: 0)
            XCTFail("should have thrown")
        } catch AmapClientError.apiStatus(let s, let info) {
            XCTAssertEqual(s, "0")
            XCTAssertEqual(info, "INVALID_KEY")
        } catch { XCTFail("wrong error: \(error)") }
    }

    func test_textSearch_parsesPois() async throws {
        let client = makeClient(json: #"""
        {"status":"1","pois":[
          {"id":"x1","name":"玄武湖","type":"风景名胜","location":"118.793,32.075","address":"南京"}
        ]}
        """#)
        let result = try await client.textSearch(query: "玄武湖")
        XCTAssertEqual(result.first?.name, "玄武湖")
        XCTAssertNil(result.first?.distanceMeters)
    }

    func test_walkingDirection_parses() async throws {
        let client = makeClient(json: #"""
        {"status":"1","route":{"paths":[{"distance":"512","duration":"360"}]}}
        """#)
        let dir = try await client.walkingDirection(
            from: .init(latitude: 32.072, longitude: 118.794),
            to:   .init(latitude: 32.080, longitude: 118.795)
        )
        XCTAssertEqual(dir.distanceMeters, 512)
        XCTAssertEqual(dir.durationSeconds, 360)
        // Bearing should be roughly north-northeast (small positive deg).
        XCTAssertGreaterThanOrEqual(dir.bearingFromOrigin, 0)
        XCTAssertLessThan(dir.bearingFromOrigin, 90)
    }

    func test_reverseGeocode_parses() async throws {
        let client = makeClient(json: #"""
        {"status":"1","regeocode":{"formatted_address":"南京市玄武区玄武湖公园"}}
        """#)
        let r = try await client.reverseGeocode(.init(latitude: 32.072, longitude: 118.794))
        XCTAssertEqual(r.formattedAddress, "南京市玄武区玄武湖公园")
    }

    func test_default_amapKey_isSpecKey() {
        XCTAssertEqual(Secrets.defaultAmapKey, "ff287a156a20b1b95830b719d6c6a047")
    }
}
