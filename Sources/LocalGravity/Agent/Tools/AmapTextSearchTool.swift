import Foundation

public final class AmapTextSearchTool: Tool {
    public let spec = ToolSpec(
        name: "amap_text_search",
        description: "Keyword POI search by free-text query. Returns up to 10 POIs.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "region": .object(["type": .string("string")])
            ]),
            "required": .array([.string("query")])
        ])
    )
    private let amap: AmapClient
    public init(amap: AmapClient) { self.amap = amap }
    public func invoke(arguments: JSONValue) async throws -> JSONValue {
        guard case .object(let o) = arguments,
              case .string(let q) = o["query"] ?? .null
        else { throw ToolError.badArguments("query required") }
        var region: String? = nil
        if case .string(let r) = o["region"] ?? .null { region = r }
        do {
            let pois = try await amap.textSearch(query: q, region: region)
            let arr = pois.map { p in
                JSONValue.object([
                    "name": .string(p.name),
                    "type": .string(p.type),
                    "address": .string(p.address),
                    "lat": .number(p.coordinate.latitude),
                    "lng": .number(p.coordinate.longitude)
                ])
            }
            return .object(["status": .string("ok"), "pois": .array(arr)])
        } catch {
            return .object(["status": .string("amap_failed"), "error": .string("\(error)")])
        }
    }
}
