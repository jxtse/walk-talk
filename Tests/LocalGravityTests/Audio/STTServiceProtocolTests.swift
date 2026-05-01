// Tests/LocalGravityTests/Audio/STTServiceProtocolTests.swift
import XCTest
@testable import LocalGravity

final class STTServiceProtocolTests: XCTestCase {
    func test_mockEmitsUtterances() throws {
        let stt = MockSTTService()
        var got: [String] = []
        try stt.start { got.append($0) }
        stt.emit("你好")
        stt.emit("世界")
        XCTAssertEqual(got, ["你好", "世界"])
    }

    func test_stopRemovesHandler() throws {
        let stt = MockSTTService()
        var got: [String] = []
        try stt.start { got.append($0) }
        stt.stop()
        stt.emit("ignored")
        XCTAssertTrue(got.isEmpty)
    }

    func test_permissionCallback_returnsConfiguredAnswer() {
        let stt = MockSTTService()
        stt.pendingPermission = false
        var answer: Bool? = nil
        stt.requestPermission { answer = $0 }
        XCTAssertEqual(answer, false)
    }
}
