import Foundation
#if canImport(UIKit)
import UIKit
#endif

public final class GetCameraFrameTool: Tool {
    public let spec = ToolSpec(
        name: "get_camera_frame",
        description: "Return the most recent camera preview frame as a base64 JPEG. Optionally accept timestamp_offset_sec to look back in time.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "timestamp_offset_sec": .object(["type": .string("number"), "default": .number(0)])
            ])
        ])
    )
    private let window: FrameWindow
    private let clock: Clock
    public init(window: FrameWindow, clock: Clock = SystemClock()) {
        self.window = window; self.clock = clock
    }
    public func invoke(arguments: JSONValue) async throws -> JSONValue {
        var offset: Double = 0
        if case .object(let o) = arguments, case .number(let n) = o["timestamp_offset_sec"] ?? .null {
            offset = n
        }
        let target = clock.now().addingTimeInterval(-offset)
        guard let f = window.latest(at: target) else {
            return .object(["status": .string("no_frame")])
        }
        #if canImport(UIKit)
        guard let jpeg = f.image.jpegData(compressionQuality: 0.7) else {
            return .object(["status": .string("encode_failed")])
        }
        let b64 = jpeg.base64EncodedString()
        return .object([
            "status": .string("ok"),
            "image_b64": .string(b64),
            "captured_at": .string(ISO8601DateFormatter().string(from: f.capturedAt))
        ])
        #else
        return .object([
            "status": .string("encode_unavailable"),
            "captured_at": .string(ISO8601DateFormatter().string(from: f.capturedAt))
        ])
        #endif
    }
}
