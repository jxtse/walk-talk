import Foundation

// MARK: - Function calling extension to LLMClient
//
// This file extends the LLMClient defined in P1 (`LLMClient.swift`) with
// OpenAI-style function-calling support. It is kept separate from the P1
// file to avoid merge conflicts between phases.
//
// Cross-phase assumption (per plan P2-T5 Step 1): the P1 `LLMClient`
// stored properties `endpoint`, `apiKey`, `session` are declared at
// `internal` access (not `private`) so this extension can reach them.
// If P1 lands them as private, change those declarations to internal —
// that is the documented fix-up.

public struct ToolCall: Codable, Equatable {
    public struct Function: Codable, Equatable {
        public let name: String
        public let arguments: String   // JSON-encoded string per OpenAI spec
        public init(name: String, arguments: String) {
            self.name = name; self.arguments = arguments
        }
    }
    public let id: String
    public let type: String   // "function"
    public let function: Function
    public init(id: String, type: String = "function", function: Function) {
        self.id = id; self.type = type; self.function = function
    }
}

public struct AssistantMessageWithTools: Codable, Equatable {
    public let role: String
    public let content: String?
    public let tool_calls: [ToolCall]?
    public init(role: String, content: String?, tool_calls: [ToolCall]?) {
        self.role = role; self.content = content; self.tool_calls = tool_calls
    }
}

public struct ChatRequestWithTools: Codable {
    public let model: String
    public let messages: [JSONValue]    // raw JSON to allow tool/assistant message shapes
    public let tools: [ToolSpec]?
    public let tool_choice: String?     // "auto" | "none"
    public let temperature: Double?
    public init(model: String,
                messages: [JSONValue],
                tools: [ToolSpec]?,
                toolChoice: String? = "auto",
                temperature: Double? = nil) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.tool_choice = toolChoice
        self.temperature = temperature
    }
}

public struct ChatResponseWithTools: Codable {
    public struct Choice: Codable {
        public let message: AssistantMessageWithTools
        public let finish_reason: String?
    }
    public let choices: [Choice]
}

extension LLMClient {
    public func chatWithTools(_ request: ChatRequestWithTools) async throws -> ChatResponseWithTools {
        var url = endpoint
        url.append(path: "/v1/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMClientError.http((response as? HTTPURLResponse)?.statusCode ?? -1,
                                       String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(ChatResponseWithTools.self, from: data)
    }
}
