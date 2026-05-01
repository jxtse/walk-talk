import Foundation

public final class AmapAroundSearchTool: Tool {
    public let spec = ToolSpec(
        name: "amap_around_search",
        description: "Search POIs near the given lat/lng. Returns up to 10 POIs with name, type, address, distance.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "lat": .object(["type": .string("number")]),
                "lng": .object(["type": .string("number")]),
                "keyword": .object(["type": .string("string")]),
                "radius": .object(["type": .string("number"), "default": .number(1000)])
            ]),
            "required": .array([.string("lat"), .string("lng")])
        ])
    )
    private let amap: AmapClient
    public init(amap: AmapClient) { self.amap = amap }
    public func invoke(arguments: JSONValue) async throws -> JSONValue {
        guard case .object(let o) = arguments,
              case .number(let lat) = o["lat"] ?? .null,
              case .number(let lng) = o["lng"] ?? .null
        else { throw ToolError.badArguments("lat,lng required") }
        var keyword: String? = nil
        if case .string(let k) = o["keyword"] ?? .null { keyword = k }
        var radius = 1000
        if case .number(let r) = o["radius"] ?? .null { radius = Int(r) }

        do {
            let pois = try await amap.aroundSearch(lat: lat, lng: lng, keyword: keyword, radius: radius)
            let arr = pois.map { p in
                JSONValue.object([
                    "name": .string(p.name),
                    "type": .string(p.type),
                    "address": .string(p.address),
                    "distance_m": .number(Double(p.distanceMeters ?? -1))
                ])
            }
            return .object(["status": .string("ok"), "pois": .array(arr)])
        } catch {
            return .object(["status": .string("amap_failed"), "error": .string("\(error)")])
        }
    }
}
