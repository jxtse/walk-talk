// Tests/LocalGravityTests/Walk/WalkSessionTests.swift
import XCTest
@testable import LocalGravity

final class WalkSessionTests: XCTestCase {
    func test_initial_isIdle() {
        let s = WalkSession.makeForTest()
        XCTAssertEqual(s.state, .idle)
    }

    func test_start_movesToWalking() async throws {
        let s = WalkSession.makeForTest()
        try await s.handle(.start)
        XCTAssertEqual(s.state, .walking)
    }

    func test_stop_fromWalking_movesToEndingThenGenerating() async throws {
        let s = WalkSession.makeForTest()
        try await s.handle(.start)
        try await s.handle(.stop)
        // ending → generating happens synchronously inside handle(.stop) for tests.
        XCTAssertEqual(s.state, .generating)
    }

    func test_keepsakeReady_movesToDone() async throws {
        let s = WalkSession.makeForTest()
        try await s.handle(.start)
        try await s.handle(.stop)
        try await s.handle(.keepsakeReady(URL(fileURLWithPath: "/tmp/x.mp4")))
        XCTAssertEqual(s.state, .done)
        XCTAssertEqual(s.keepsakeURL?.path, "/tmp/x.mp4")
    }

    func test_keepsakeFailed_movesToFailed() async throws {
        let s = WalkSession.makeForTest()
        try await s.handle(.start)
        try await s.handle(.stop)
        try await s.handle(.keepsakeFailed("nope"))
        XCTAssertEqual(s.state, .failed)
        XCTAssertEqual(s.lastError, "nope")
    }

    func test_doubleStart_throws() async throws {
        let s = WalkSession.makeForTest()
        try await s.handle(.start)
        do {
            try await s.handle(.start)
            XCTFail("expected throw")
        } catch WalkSessionError.invalidTransition {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
