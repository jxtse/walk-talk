# P1 close-out

**Date:** 2026-05-02
**Branch:** main

## Project layout note

Implementation host has no Mac toolchain (Windows MinGW64). The project is
laid out as a Swift Package (`Package.swift` at the repo root) instead of
an `.xcodeproj`. Module code lives under `Sources/LocalGravity/`, the
`@main` SwiftUI entry under `Sources/LocalGravityApp/`, and tests under
`Tests/LocalGravityTests/`. Plan paths `WalkTalk/<dir>/<file>` map to
`Sources/LocalGravity/<dir>/<file>`. Migration to `.xcodeproj` is
documented in `docs/sdk-setup.md` and `Resources/README.md`.

## Unit tests

Tests written for every P1 deliverable. **Verification deferred to Mac
CI** — they cannot be run from this host.

| Suite | File |
|---|---|
| Smoke | `Tests/LocalGravityTests/SmokeTests.swift` |
| Camera mock | `Tests/LocalGravityTests/Camera/CameraBridgeMockTests.swift` |
| TrackBuffer | `Tests/LocalGravityTests/Location/TrackBufferTests.swift` |
| LLMClient | `Tests/LocalGravityTests/Net/LLMClientTests.swift` |
| AmapClient | `Tests/LocalGravityTests/Amap/AmapClientTests.swift` |

## On-device smoke results

Not run — no Mac available. Each `RootView` button is wired but the
camera + map paths will surface their LOOKUP errors until the SDKs are
linked on a Mac.

| Pillar | Status |
|---|---|
| Camera | lookup-pending (LOOKUP-1..8 in Insta360CameraBridge.swift) |
| Location | code complete; needs on-device run with location permissions |
| Map | lookup-pending (LOOKUP-AMAP-1..5 across MapPreviewView / app init) |
| LLM | code complete; needs Tailscale to reach 100.99.139.20:18141 |

## LOOKUPs still open

- `Sources/LocalGravity/Camera/Insta360CameraBridge.swift` — LOOKUP-1..8
- `Sources/LocalGravityApp/LocalGravityApp.swift` — LOOKUP-AMAP-2 (key reg)
- `Sources/LocalGravity/Map/MapPreviewView.swift` — LOOKUP-AMAP-3..5
- `Resources/Info.plist` — LOOKUP for exact Bonjour service identifiers

## Known gaps going into P2

- Insta360 SDK binary not vendored. Engineer on Mac must drop the
  framework into `Frameworks/` per `docs/sdk-setup.md`.
- 高德 SDK binary similarly not vendored; SPM mirror or .framework link
  is a Mac-side task.
- `Secrets.plist` is gitignored. Default Amap key
  `ff287a156a20b1b95830b719d6c6a047` is wired as the env-var fallback;
  the OpenAI-compatible LLM endpoint defaults to
  `http://100.99.139.20:18141`.
- The `RootView` "4. LLM ping" button uses model id placeholder
  `REPLACE_WITH_MODEL_FROM_A4`; pick the real model after the A4 spike.

## Out-of-scope (touched only in later phases)

- `Sources/LocalGravity/Agent/` (P2)
- `Sources/LocalGravity/Walk/` aka `Session/` (P3)
- `Sources/LocalGravity/Audio/` (P3)
- `Sources/LocalGravity/Keepsake/` (P4–P5)
- `Sources/LocalGravity/UI/` (P3+)

P1 is complete to the "code-only, verification-deferred" bar described in
the plan preamble.
