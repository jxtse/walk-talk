import Foundation

public enum AgentTrigger {
    case userSpoke(String)             // STT result
    case locationTick                  // periodic timer; agent decides whether to recommend
    case sessionEnded                  // (used in P5; agent emits a final wrap-up)
}

public struct AgentTurnResult {
    public let toolCalls: [(name: String, args: JSONValue, result: JSONValue)]
    public let finalContent: String?   // last assistant text, if any
}

public final class AgentRuntime {
    private let llm: LLMClient
    private let model: String
    private let tools: ToolRegistry
    private let systemPrompt: String
    private let maxIterations: Int

    public init(llm: LLMClient,
                model: String,
                tools: ToolRegistry,
                systemPrompt: String = SystemPrompt.text,
                maxIterations: Int = 6) {
        self.llm = llm; self.model = model; self.tools = tools
        self.systemPrompt = systemPrompt; self.maxIterations = maxIterations
    }

    public func handle(_ trigger: AgentTrigger, contextHints: [String: String] = [:]) async throws -> AgentTurnResult {
        let triggerMsg = Self.triggerDescription(trigger, hints: contextHints)
        var messages: [JSONValue] = [
            .object(["role": .string("system"), "content": .string(systemPrompt)]),
            .object(["role": .string("user"), "content": .string(triggerMsg)])
        ]

        var collected: [(String, JSONValue, JSONValue)] = []
        var finalText: String? = nil

        for _ in 0..<maxIterations {
            let req = ChatRequestWithTools(
                model: model,
                messages: messages,
                tools: tools.specs,
                toolChoice: "auto",
                temperature: 0.4
            )
            let resp = try await llm.chatWithTools(req)
            guard let choice = resp.choices.first else { break }
            let msg = choice.message

            // Append assistant message to history
            var assistantObj: [String: JSONValue] = [
                "role": .string("assistant"),
                "content": msg.content.map(JSONValue.string) ?? .null
            ]
            if let calls = msg.tool_calls {
                let arr = calls.map { c in
                    JSONValue.object([
                        "id": .string(c.id),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(c.function.name),
                            "arguments": .string(c.function.arguments)
                        ])
                    ])
                }
                assistantObj["tool_calls"] = .array(arr)
            }
            messages.append(.object(assistantObj))

            // If no tool calls, we're done.
            guard let calls = msg.tool_calls, !calls.isEmpty else {
                finalText = msg.content
                break
            }

            // Execute each tool call sequentially (simplest correct semantics).
            for call in calls {
                let argsJson = call.function.arguments.data(using: .utf8) ?? Data()
                let args = (try? JSONDecoder().decode(JSONValue.self, from: argsJson)) ?? .null
                let result: JSONValue
                do {
                    result = try await tools.invoke(name: call.function.name, arguments: args)
                } catch {
                    result = .object(["status": .string("tool_error"),
                                      "error": .string("\(error)")])
                }
                collected.append((call.function.name, args, result))
                let resultStr = (try? String(data: JSONEncoder().encode(result), encoding: .utf8)) ?? "null"
                messages.append(.object([
                    "role": .string("tool"),
                    "tool_call_id": .string(call.id),
                    "name": .string(call.function.name),
                    "content": .string(resultStr ?? "null")
                ]))
            }
        }

        return AgentTurnResult(toolCalls: collected, finalContent: finalText)
    }

    private static func triggerDescription(_ t: AgentTrigger, hints: [String: String]) -> String {
        let h = hints.map { "[\($0.key)=\($0.value)]" }.joined(separator: " ")
        switch t {
        case .userSpoke(let s):
            return "用户刚说：\(s)\n\(h)"
        case .locationTick:
            return "系统位置 tick：现在是检查附近是否值得推荐 POI 的时机。\n\(h)"
        case .sessionEnded:
            return "散步结束。简短告别。\n\(h)"
        }
    }
}
