// Tests/LocalGravityTests/Audio/TTSServiceTests.swift
//
// P3-T3 tests: focus on the timeout/fallback policy of CompositeTTSService.
// We cannot exercise real `LocalTTS` (AVSpeechSynthesizer needs audio HW)
// or real `RemoteTTS` (network) inside an SPM unit test, so we substitute
// stub `Speaker`s.
import XCTest
@testable import LocalGravity

private final class CountingSpeaker: TTSService {
    var spoken: [String] = []
    func speak(_ text: String) async throws { spoken.append(text) }
    func cancel() {}
}

private final class SlowSpeaker: TTSService {
    let delay: TimeInterval
    var spoken: [String] = []
    init(_ d: TimeInterval) { delay = d }
    func speak(_ text: String) async throws {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        spoken.append(text)
    }
    func cancel() {}
}

private final class FailingSpeaker: TTSService {
    struct Boom: Error {}
    func speak(_ text: String) async throws { throw Boom() }
    func cancel() {}
}

final class TTSServiceTests: XCTestCase {

    func test_compositeUsesLocalWhenRemoteIsNil() async throws {
        let local = CountingSpeaker()
        let svc = CompositeTTSService(remote: nil, local: local, remoteTimeout: 0.1)
        try await svc.speak("你好")
        XCTAssertEqual(local.spoken, ["你好"])
    }

    func test_compositePrefersRemoteWhenFastEnough() async throws {
        let remote = CountingSpeaker()
        let local = CountingSpeaker()
        let svc = CompositeTTSService(remote: remote, local: local, remoteTimeout: 1.5)
        try await svc.speak("hi")
        XCTAssertEqual(remote.spoken, ["hi"])
        XCTAssertEqual(local.spoken, [], "local should not have been called when remote succeeded")
    }

    func test_compositeFallsBackToLocalOnRemoteTimeout() async throws {
        let remote = SlowSpeaker(0.5)
        let local = CountingSpeaker()
        let svc = CompositeTTSService(remote: remote, local: local, remoteTimeout: 0.05)
        try await svc.speak("late")
        XCTAssertEqual(local.spoken, ["late"], "should have degraded to local once remote exceeded the 50ms test budget")
    }

    func test_compositeFallsBackToLocalOnRemoteFailure() async throws {
        let local = CountingSpeaker()
        let svc = CompositeTTSService(remote: FailingSpeaker(), local: local, remoteTimeout: 1.5)
        try await svc.speak("oops")
        XCTAssertEqual(local.spoken, ["oops"])
    }

    func test_withTimeout_returnsValueWhenFastEnough() async throws {
        let v = try await CompositeTTSService.withTimeout(1.0) { 42 }
        XCTAssertEqual(v, 42)
    }

    func test_withTimeout_throwsWhenSlow() async {
        do {
            _ = try await CompositeTTSService.withTimeout(0.05) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return 1
            }
            XCTFail("expected timeout")
        } catch is TTSTimeout {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
