// Tests/LocalGravityTests/Camera/CameraBridgeMockTests.swift
import XCTest
@testable import LocalGravity

final class CameraBridgeMockTests: XCTestCase {
    func test_connect_setsIsConnectedTrue() async throws {
        let bridge = MockCameraBridge()
        try await bridge.connect()
        XCTAssertTrue(bridge.isConnected)
    }

    func test_connect_throwsWhenConfigured() async {
        let bridge = MockCameraBridge()
        bridge.connectShouldThrow = true
        do {
            try await bridge.connect()
            XCTFail("should have thrown")
        } catch CameraBridgeError.underlying {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_startRecording_failsIfNotConnected() async {
        let bridge = MockCameraBridge()
        do {
            try await bridge.startRecording()
            XCTFail("should have thrown")
        } catch CameraBridgeError.notConnected {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_recording_lifecycle_returnsHandle() async throws {
        let bridge = MockCameraBridge()
        try await bridge.connect()
        try await bridge.startRecording()
        let handle = try await bridge.stopRecording()
        XCTAssertEqual(handle.id, "mock-video-001")
        XCTAssertEqual(handle.approxDurationSec, 30.0)
    }

    func test_stopRecording_failsIfNotRecording() async throws {
        let bridge = MockCameraBridge()
        try await bridge.connect()
        do {
            _ = try await bridge.stopRecording()
            XCTFail("should have thrown")
        } catch CameraBridgeError.notRecording {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_downloadVideo_writesNonEmptyFile() async throws {
        let bridge = MockCameraBridge()
        try await bridge.connect()
        try await bridge.startRecording()
        let handle = try await bridge.stopRecording()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try await bridge.downloadVideo(handle, to: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attrs[.size] as? Int, 8)
    }

    func test_emitOneFrame_deliversAFrame() {
        let bridge = MockCameraBridge()
        var got: PreviewFrame?
        bridge.emitOneFrame { got = $0 }
        XCTAssertNotNil(got)
    }
}
