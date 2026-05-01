# P2-T7 — Live agent dry-run (deferred to Mac)

**Status:** Code-side scope of P2-T7 cannot be completed from the Windows
worktree because it requires modifying `Sources/LocalGravity/App/RootView.swift`
inside an Xcode project that does not yet exist on this machine (P1 is being
written in parallel; the SwiftUI app target is Mac-only). The unit-test
substance of P2 (tasks T1–T6) is complete and committed.

This note records what the Mac engineer must do to satisfy P2-T7.

## Goal

A button in `RootView` that runs the **real** `LLMClient` against the **real**
`ToolRegistry`, with mocked `Speaker` / `VLMAnalyzer` / `AmapClient`.
Confirms that `SystemPrompt.text` + the published `ToolSpec`s compose into
something the live model at `100.99.139.20:18141` actually uses correctly.

## Required edits (on Mac)

Add to `Sources/LocalGravity/App/RootView.swift` (or wherever the SwiftUI
RootView ends up living):

```swift
Button("5. Agent dry-run") {
    Task {
        let speaker = LoggingSpeaker { lastResult.append("\nspoken: \($0)") }
        let registry = ToolRegistry([
            SpeakToUserTool(speaker: speaker, quota: nil),
            RecordMomentTool(log: MomentLog(), trackBuffer: TrackBuffer())
        ])
        let agent = AgentRuntime(
            llm: LLMClient(),
            model: "REPLACE_WITH_MODEL_FROM_A4",
            tools: registry
        )
        do {
            let r = try await agent.handle(.userSpoke("帮我打个招呼"))
            lastResult = "tool calls: \(r.toolCalls.map(\.name))\ntext: \(r.finalContent ?? "<none>")"
        } catch {
            lastResult = "agent failed: \(error)"
        }
    }
}

final class LoggingSpeaker: Speaker {
    let onSpeak: (String) -> Void
    init(_ f: @escaping (String) -> Void) { onSpeak = f }
    func speak(_ text: String) async throws { onSpeak(text) }
}
```

## Run procedure

1. Build & run on a real iPhone with VPN/Tailscale active (per A3).
2. Tap **Agent dry-run**.
3. Expected: agent calls `speak_to_user` once with a short greeting; no
   other tools; returns `<none>` final content (or empty string).
4. If the live model misbehaves (invents tool names, ignores quota, talks
   too long), iterate `SystemPrompt.swift` and re-run. Each prompt change
   = its own commit (`feat(p2): tighten system prompt — <reason>`).

## Acceptance criteria checklist

- [ ] Greeting scenario succeeds (single `speak_to_user` call).
- [ ] When `quota` is overridden to 0, model emits the call but
      `SpeakToUserTool` returns `quota_exceeded` and Speaker is not invoked.
- [ ] Model does **not** invent non-existent tool names; if it does, capture
      the names verbatim and tighten the prompt.

## Cross-phase signatures assumed

`AgentRuntime` and the 8 tools were written against these expected
P1 signatures (per the plan). If P1 lands different shapes, fix on Mac:

- `LLMClient(endpoint:apiKey:session:)` ctor with `internal` storage of
  `endpoint`, `apiKey`, `session` so `LLMClient+Tools.swift` can reach them.
- `LLMClientError.http(Int, String)` enum case.
- `TrackBuffer` with `append(_ TrackPoint)` and `snapshot: [TrackPoint]`.
- `TrackPoint(coordinate:timestamp:horizontalAccuracy:)`.
- `AmapClient` with `aroundSearch / textSearch / walkingDirection /
  reverseGeocode` per plan §P1-T8.
- `AmapPOI(id:name:type:address:coordinate:distanceMeters:)`.
- `AmapClient.WalkingDirection(distanceMeters:durationSeconds:bearingFromOrigin:)`.
- `AmapClient.GeoResult(formattedAddress:coordinate:)`.
- `PreviewFrame(image: UIImage, capturedAt: Date)` from `Camera/CameraBridge.swift`.
