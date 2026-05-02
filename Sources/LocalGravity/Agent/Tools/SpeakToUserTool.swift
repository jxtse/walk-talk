import Foundation

public final class SpeakToUserTool: Tool {
    public let spec = ToolSpec(
        name: "speak_to_user",
        description: "Speak the given text to the user via earphones. Must be brief and conversational.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object(["type": .string("string"), "description": .string("≤30 字的口语")])
            ]),
            "required": .array([.string("text")])
        ])
    )
    private let speaker: Speaker
    private let quota: ProactiveQuota?
    /// If `proactive` is true, decrements the quota (used for AI-initiated turns).
    /// Passive replies pass `proactive: false`.
    public init(speaker: Speaker, quota: ProactiveQuota? = nil) {
        self.speaker = speaker; self.quota = quota
    }

    public func invoke(arguments: JSONValue) async throws -> JSONValue {
        guard case .object(let o) = arguments, case .string(let text) = o["text"] ?? .null
        else { throw ToolError.badArguments("missing text") }
        if let quota, !quota.canSpeak() {
            return .object(["status": .string("quota_exceeded")])
        }
        try await speaker.speak(text)
        quota?.recordSpoken()
        return .object(["status": .string("spoken")])
    }
}
