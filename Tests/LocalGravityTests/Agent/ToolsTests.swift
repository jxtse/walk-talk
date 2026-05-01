import XCTest
import CoreLocation
@testable import LocalGravity
#if canImport(UIKit)
import UIKit
#endif

final class ToolsTests: XCTestCase {
    // MARK: - Speaker
    final class SpyEnv: Speaker, VLMAnalyzer {
        var spoken: [String] = []
        var vlmAnswer: String = "看起来像樱花"
        func speak(_ text: String) async throws { spoken.append(text) }
        func analyze(imageB64: String, question: String) async throws -> String { vlmAnswer }
    }

    func test_speakToUser_recordsAndConsumes() async throws {
        let env = SpyEnv()
        let q = ProactiveQuota(limit: 1, window: 600, clock: FakeClock())
        let tool = SpeakToUserTool(speaker: env, quota: q)
        let r = try await tool.invoke(arguments: .object(["text": .string("你好")]))
        XCTAssertEqual(env.spoken, ["你好"])
        guard case .object(let o) = r, case .string(let s) = o["status"] ?? .null else { return XCTFail() }
        XCTAssertEqual(s, "spoken")
        XCTAssertFalse(q.canSpeak())
    }

    func test_speakToUser_returnsQuotaExceeded() async throws {
        let env = SpyEnv()
        let q = ProactiveQuota(limit: 0, window: 600, clock: FakeClock())
        let tool = SpeakToUserTool(speaker: env, quota: q)
        let r = try await tool.invoke(arguments: .object(["text": .string("hi")]))
        guard case .object(let o) = r, case .string(let s) = o["status"] ?? .null else { return XCTFail() }
        XCTAssertEqual(s, "quota_exceeded")
        XCTAssertTrue(env.spoken.isEmpty)
    }

    func test_recordMoment_writesToLog() async throws {
        let log = MomentLog()
        let buf = TrackBuffer()
        buf.append(TrackPoint(coordinate: .init(latitude: 32.07, longitude: 118.79),
                              timestamp: Date(), horizontalAccuracy: 5))
        let tool = RecordMomentTool(log: log, trackBuffer: buf)
        _ = try await tool.invoke(arguments: .object([
            "kind": .string("idea"), "context": .string("研究 idea")
        ]))
        XCTAssertEqual(log.snapshot().count, 1)
        XCTAssertEqual(log.snapshot().first?.kind, .idea)
        XCTAssertNotNil(log.snapshot().first?.coordinate)
    }

    #if canImport(UIKit)
    func test_getCameraFrame_returnsLatest() async throws {
        let win = FrameWindow()
        let img = UIGraphicsImageRenderer(size: .init(width: 4, height: 4)).image { ctx in
            UIColor.red.setFill(); ctx.fill(.init(x: 0, y: 0, width: 4, height: 4))
        }
        win.append(PreviewFrame(image: img, capturedAt: Date()))
        let tool = GetCameraFrameTool(window: win)
        let r = try await tool.invoke(arguments: .object([:]))
        guard case .object(let o) = r, case .string(let s) = o["status"] ?? .null else { return XCTFail() }
        XCTAssertEqual(s, "ok")
    }

    func test_getCameraFrame_noFrame() async throws {
        let tool = GetCameraFrameTool(window: FrameWindow())
        let r = try await tool.invoke(arguments: .object([:]))
        guard case .object(let o) = r, case .string(let s) = o["status"] ?? .null else { return XCTFail() }
        XCTAssertEqual(s, "no_frame")
    }
    #endif

    func test_analyzeFrameVLM_ok() async throws {
        let env = SpyEnv()
        let tool = AnalyzeFrameVLMTool(vlm: env)
        let r = try await tool.invoke(arguments: .object([
            "image_b64": .string("AAA"), "question": .string("what?")
        ]))
        guard case .object(let o) = r, case .string(let s) = o["answer"] ?? .null else { return XCTFail() }
        XCTAssertEqual(s, "看起来像樱花")
    }
}
