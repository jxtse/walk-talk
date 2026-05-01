import Foundation

public final class AmapGeoTool: Tool {
    public let spec = ToolSpec(
        name: "amap_regeocode",
        description: "Reverse-geocode lat/lng to a Chinese formatted address.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "lat": .object(["type": .string("number")]),
                "lng": .object(["type": .string("number")])
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
        do {
            let r = try await amap.reverseGeocode(.init(latitude: lat, longitude: lng))
            return .object(["status": .string("ok"), "address": .string(r.formattedAddress)])
        } catch {
            return .object(["status": .string("amap_failed"), "error": .string("\(error)")])
        }
    }
}
