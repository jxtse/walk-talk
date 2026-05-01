import Foundation

public protocol VLMAnalyzer {
    /// `imageB64` is JPEG base64; returns a short Chinese description / answer.
    func analyze(imageB64: String, question: String) async throws -> String
}

public final class AnalyzeFrameVLMTool: Tool {
    public let spec = ToolSpec(
        name: "analyze_frame_vlm",
        description: "Send an image (base64 JPEG) plus a question to the VLM and return the textual answer.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "image_b64": .object(["type": .string("string")]),
                "question": .object(["type": .string("string")])
            ]),
            "required": .array([.string("image_b64"), .string("question")])
        ])
    )
    private let vlm: VLMAnalyzer
    public init(vlm: VLMAnalyzer) { self.vlm = vlm }
    public func invoke(arguments: JSONValue) async throws -> JSONValue {
        guard case .object(let o) = arguments,
              case .string(let img) = o["image_b64"] ?? .null,
              case .string(let q) = o["question"] ?? .null
        else { throw ToolError.badArguments("image_b64 + question required") }
        do {
            let answer = try await vlm.analyze(imageB64: img, question: q)
            return .object(["status": .string("ok"), "answer": .string(answer)])
        } catch {
            return .object(["status": .string("vlm_failed"), "error": .string("\(error)")])
        }
    }
}
