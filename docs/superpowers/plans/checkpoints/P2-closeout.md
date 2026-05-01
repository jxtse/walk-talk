# P2 close-out

**Date:** 2026-05-02
**Tests:** all unit tests written, **execution deferred to Mac** (Windows
worktree has no `swift` / `xcodebuild`). Tests added in this batch:

- `Tests/LocalGravityTests/Agent/ToolRegistryTests.swift` — 2 tests
- `Tests/LocalGravityTests/Agent/ProactiveQuotaTests.swift` — 4 tests
- `Tests/LocalGravityTests/Agent/ToolsTests.swift` — 6 tests
- `Tests/LocalGravityTests/Agent/AgentRuntimeTests.swift` — 5 tests
  (covers all 5 ScriptedLLM scenarios required by spec §3:
  passive Q&A · proactive accepted · quota-exceeded rejection ·
  passive capture (record_moment) · silent default)
- `Tests/LocalGravityTests/LLM/LLMClientToolCallTests.swift` — 1 test

**Live agent observations (model = TBD on Mac):** _deferred — see
`docs/superpowers/plans/checkpoints/P2-T7-agent-dry-run.md` for the
script the engineer must run on Mac with VPN active._

- Greeting scenario: _pending Mac run_
- Quota respected when overridden: _pending Mac run_
- Did model invent any non-existent tool name? _pending Mac run_

**Prompt iterations made:** none yet (initial prompt only).

**Open issues going into P3:**
- P2-T7 live dry-run still owed; cannot be done from Windows worktree.
- Cross-phase signature assumptions (see P2-T7 doc) need verification
  once P1 lands. Of particular concern:
  - `LLMClient` storage must be `internal` (not `private`) for
    `LLMClient+Tools.swift` to reach `endpoint`, `apiKey`, `session`.
  - If P1 uses different `AmapClient` / `TrackBuffer` / `PreviewFrame`
    signatures, the 4 Amap tools and `RecordMomentTool` /
    `GetCameraFrameTool` will need a small fix-up commit.
- `StubURLProtocol` is declared in P1's `LLMClientTests`. The P2 test file
  `LLMClientToolCallTests.swift` introduces `StubURLProtocolP2` to avoid
  duplicate-class collisions; the AgentRuntime tests use yet a third
  `ScriptedURLProtocol` for the ordered-script behaviour. Mac engineer
  may want to consolidate these once everything builds.

**SPM-vs-Xcode mapping note (Windows constraint):**
Plan paths `WalkTalk/Agent/...` and `WalkTalkTests/Agent/...` were
mapped to `Sources/LocalGravity/Agent/...` and
`Tests/LocalGravityTests/Agent/...` per the Phase-2 environment caveat.
Same shape, different package layout. No source content changes beyond
file location and module name (`@testable import LocalGravity`).
