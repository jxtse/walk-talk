import Foundation
import CoreLocation

public final class RecordMomentTool: Tool {
    public let spec = ToolSpec(
        name: "record_moment",
        description: "Silently record a notable moment (idea/place/vibe) at the user's current GPS.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "kind": .object(["type": .string("string"), "enum": .array([.string("idea"), .string("place"), .string("vibe")])]),
                "context": .object(["type": .string("string")])
            ]),
            "required": .array([.string("kind"), .string("context")])
        ])
    )
    private let log: MomentLog
    private let trackBuffer: TrackBuffer
    private let clock: Clock
    public init(log: MomentLog, trackBuffer: TrackBuffer, clock: Clock = SystemClock()) {
        self.log = log; self.trackBuffer = trackBuffer; self.clock = clock
    }

    public func invoke(arguments: JSONValue) async throws -> JSONValue {
        guard case .object(let o) = arguments,
              case .string(let kindStr) = o["kind"] ?? .null,
              case .string(let ctx) = o["context"] ?? .null,
              let kind = Moment.Kind(rawValue: kindStr)
        else { throw ToolError.badArguments("kind+context required") }
        let now = clock.now()
        let coord = trackBuffer.snapshot.last?.coordinate
        log.add(Moment(kind: kind, context: ctx, coordinate: coord, timestamp: now))
        return .object(["status": .string("recorded")])
    }
}
