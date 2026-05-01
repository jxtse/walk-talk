import Foundation

/// JSON-schema-style description of a tool, in the OpenAI function-calling shape.
public struct ToolSpec: Codable, Equatable {
    public struct Function: Codable, Equatable {
        public let name: String
        public let description: String
        public let parameters: JSONValue   // JSON Schema
    }
    public let type: String   // always "function"
    public let function: Function
    public init(name: String, description: String, parameters: JSONValue) {
        self.type = "function"
        self.function = Function(name: name, description: description, parameters: parameters)
    }
}

/// Minimal JSON value type so we can hand-build schemas in Swift.
public indirect enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown json")
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

public protocol Tool {
    var spec: ToolSpec { get }
    /// Execute with raw JSON arguments (as the LLM emits). Returns a JSON-encodable result.
    func invoke(arguments: JSONValue) async throws -> JSONValue
}

public enum ToolError: Error, Equatable {
    case unknownTool(String)
    case badArguments(String)
    case underlying(String)
}
