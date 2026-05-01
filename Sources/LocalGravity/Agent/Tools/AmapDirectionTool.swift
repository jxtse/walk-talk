import Foundation
import CoreLocation

public final class AmapDirectionTool: Tool {
    public let spec = ToolSpec(
        name: "amap_direction_walking",
        description: "Compute walking distance/duration and bearing from origin to destination. Use for 'guide me there', NOT for turn-by-turn nav.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "from_lat": .object(["type": .string("number")]),
                "from_lng": .object(["type": .string("number")]),
                "to_lat": .object(["type": .string("number")]),
                "to_lng": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("from_lat"), .string("from_lng"), .string("to_lat"), .string("to_lng")])
        ])
    )
    private let amap: AmapClient
    public init(amap: AmapClient) { self.amap = amap }
    public func invoke(arguments: JSONValue) async throws -> JSONValue {
        guard case .object(let o) = arguments,
              case .number(let fLat) = o["from_lat"] ?? .null,
              case .number(let fLng) = o["from_lng"] ?? .null,
              case .number(let tLat) = o["to_lat"] ?? .null,
              case .number(let tLng) = o["to_lng"] ?? .null
        else { throw ToolError.badArguments("4 coords required") }
        do {
            let d = try await amap.walkingDirection(
                from: .init(latitude: fLat, longitude: fLng),
                to: .init(latitude: tLat, longitude: tLng))
            return .object([
                "status": .string("ok"),
                "distance_m": .number(Double(d.distanceMeters)),
                "duration_s": .number(Double(d.durationSeconds)),
                "bearing_deg": .number(d.bearingFromOrigin),
                "compass": .string(Self.compass(d.bearingFromOrigin))
            ])
        } catch {
            return .object(["status": .string("amap_failed"), "error": .string("\(error)")])
        }
    }
    private static func compass(_ deg: Double) -> String {
        let dirs = ["北","东北","东","东南","南","西南","西","西北"]
        let normalized = (deg + 22.5).truncatingRemainder(dividingBy: 360)
        let safe = normalized < 0 ? normalized + 360 : normalized
        let idx = Int(safe / 45) % 8
        return dirs[idx]
    }
}
