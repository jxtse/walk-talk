import Foundation

public final class ToolRegistry {
    private(set) var tools: [String: Tool] = [:]

    public init(_ tools: [Tool] = []) {
        tools.forEach { register($0) }
    }

    public func register(_ tool: Tool) {
        tools[tool.spec.function.name] = tool
    }

    public var specs: [ToolSpec] { Array(tools.values.map { $0.spec }) }

    public func invoke(name: String, arguments: JSONValue) async throws -> JSONValue {
        guard let t = tools[name] else { throw ToolError.unknownTool(name) }
        return try await t.invoke(arguments: arguments)
    }
}
