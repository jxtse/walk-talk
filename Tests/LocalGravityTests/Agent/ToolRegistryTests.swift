import XCTest
@testable import LocalGravity

final class FakeEcho: Tool {
    let spec = ToolSpec(
        name: "echo",
        description: "echo a string",
        parameters: .object([
            "type": .string("object"),
            "properties": .object(["msg": .object(["type": .string("string")])]),
            "required": .array([.string("msg")])
        ])
    )
    func invoke(arguments: JSONValue) async throws -> JSONValue {
        guard case .object(let o) = arguments, case .string(let s) = o["msg"] ?? .null
        else { throw ToolError.badArguments("missing msg") }
        return .object(["echo": .string(s)])
    }
}

final class ToolRegistryTests: XCTestCase {
    func test_register_and_invoke() async throws {
        let reg = ToolRegistry([FakeEcho()])
        let r = try await reg.invoke(name: "echo", arguments: .object(["msg": .string("hi")]))
        guard case .object(let o) = r, case .string(let s) = o["echo"] ?? .null else {
            return XCTFail("wrong shape")
        }
        XCTAssertEqual(s, "hi")
    }

    func test_unknownTool_throws() async {
        let reg = ToolRegistry()
        do { _ = try await reg.invoke(name: "nope", arguments: .null); XCTFail() }
        catch ToolError.unknownTool(let n) { XCTAssertEqual(n, "nope") }
        catch { XCTFail("\(error)") }
    }
}
