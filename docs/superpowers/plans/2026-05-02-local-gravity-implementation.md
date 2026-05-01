# Local Gravity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an audio-first AI walking-companion iOS app paired with an Insta360 camera. During the walk the user keeps the phone in pocket, talks to the AI through earphones; after the walk the app produces a short keepsake video (with poster fallback).

**Architecture:** Single iOS native app (Swift / SwiftUI). Inside it: a `WalkSession` state machine drives `CameraBridge` (Insta360 SDK), `LocationSvc` (CoreLocation), `AudioIO` (AVFoundation + STT/TTS). All cognition flows through one `AgentRuntime` running a ReAct loop against an OpenAI-compatible endpoint, with tools for camera frames, VLM analysis, Amap POI/geo, TTS, and moment recording. After the walk a `KeepsakeBuilder` collects materials, asks the LLM for a "script", and assembles a short video via `AVFoundation` (poster-only fallback path always available).

**Tech Stack:** Swift 5.9+ / iOS 17+ / SwiftUI + UIKit interop / Xcode 15+ / Swift Package Manager / XCTest / `async`/`await` / `URLSession` / `Combine` for event streams / AVFoundation / CoreLocation / Speech (STT) / AVSpeechSynthesizer or remote TTS / Insta360 iOS SDK / 高德 iOS SDK (AMapFoundation + AMapSearch + MAMapKit) / OpenAI-compatible HTTP API at `http://100.99.139.20:18141`.

**Source spec:** `docs/superpowers/specs/2026-05-02-local-gravity-design.md`

---

## How to read this plan

The plan is split into seven phases that mirror the spec's §8 timeline plus a phase-zero "spike" for §9 unverified assumptions:

| Phase | Spec mapping | Goal |
|---|---|---|
| **P0 — Assumption Spike** | §9 | Resolve all 6 unverified assumptions before they invalidate downstream work |
| **P1 — Foundations (W1–W2)** | §8 W1–W2 | Empty Xcode project → 4 SDKs each demonstrably reachable in isolation |
| **P2 — Agent Skeleton (W3–W4)** | §8 W3–W4 | ReAct runtime + tool set v1 with mocked dependencies, tested |
| **P3 — Walk Loop (W5–W6)** | §8 W5–W6 | End-to-end "leave the house, walk 30 min, return" works on a real device |
| **P4 — Keepsake v1 / Poster fallback (W7–W8)** | §8 W7–W8 | After-walk poster always produced, even if everything else failed |
| **P5 — Keepsake v2 / Short video (W9–W10)** | §8 W9–W10 | AVFoundation video assembly with auto-fallback to poster |
| **P6 — Field & Demo (W11–W12)** | §8 W11–W12 | 3 real walks at 玄武湖, demo rehearsal with degradation paths |

**Each task block** has the form:
1. Files (create/modify/test)
2. Bite-sized steps with code blocks and exact commands
3. Commit step at the end

**SDK realism note:** The Insta360 iOS SDK and the 高德 iOS SDK are vendor SDKs with API surfaces I do not have line-by-line authority over. Tasks that touch them define the **shape and responsibility of the bridge class** with TODO markers like `// LOOKUP: see Insta360 docs §X — exact method name for "start preview stream"`. The engineer must look up the exact method name from the vendor docs / sample code at that point. Every such TODO has the precise question to answer; none is open-ended.

**Commits:** every task ends with a commit. Use Conventional Commits (`feat:`, `test:`, `chore:`, `docs:`, `fix:`, `refactor:`).

---

## File Structure (high-level)

```
walk-talk/
├── WalkTalk.xcodeproj              # Xcode project (P1-T1)
├── Package.swift                   # SPM manifest if we extract any module (later)
├── WalkTalk/                       # main app target
│   ├── App/
│   │   ├── WalkTalkApp.swift       # @main entry
│   │   └── RootView.swift
│   ├── Session/
│   │   ├── WalkSession.swift       # state machine: idle→walking→ending→generating→done
│   │   └── WalkSessionEvents.swift # event/log types
│   ├── Camera/
│   │   ├── CameraBridge.swift      # protocol
│   │   ├── Insta360CameraBridge.swift
│   │   ├── MockCameraBridge.swift  # for unit tests / simulator
│   │   └── FrameWindow.swift       # 5-min sliding window of sampled frames
│   ├── Location/
│   │   ├── LocationSvc.swift
│   │   └── TrackBuffer.swift       # 30-min GPS buffer
│   ├── Audio/
│   │   ├── AudioIO.swift           # mic in + speaker out coordinator
│   │   ├── STTService.swift        # Speech framework wrapper
│   │   └── TTSService.swift        # AVSpeechSynthesizer or remote TTS
│   ├── Agent/
│   │   ├── AgentRuntime.swift      # ReAct loop
│   │   ├── ToolRegistry.swift
│   │   ├── Tools/
│   │   │   ├── AmapAroundSearchTool.swift
│   │   │   ├── AmapTextSearchTool.swift
│   │   │   ├── AmapDirectionTool.swift
│   │   │   ├── AmapGeoTool.swift
│   │   │   ├── GetCameraFrameTool.swift
│   │   │   ├── AnalyzeFrameVLMTool.swift
│   │   │   ├── RecordMomentTool.swift
│   │   │   └── SpeakToUserTool.swift
│   │   ├── ProactiveQuota.swift    # ≤3 / 10min counter
│   │   └── SystemPrompt.swift      # the AI behavior contract baked into prompt
│   ├── Net/
│   │   ├── LLMClient.swift         # OpenAI-compatible HTTP client
│   │   ├── AmapClient.swift        # HTTP wrapper for amap REST/SDK calls
│   │   └── DiffusionClient.swift   # one-shot image gen
│   ├── Map/
│   │   └── MapRenderer.swift       # 高德 SDK basemap + track export
│   ├── Keepsake/
│   │   ├── KeepsakeBuilder.swift   # orchestrator
│   │   ├── MaterialCollector.swift
│   │   ├── ScriptGenerator.swift   # one LLM call → structured script
│   │   ├── PosterComposer.swift    # always-works fallback
│   │   ├── VideoAssembler.swift    # AVFoundation composition
│   │   └── KeepsakeFallback.swift  # decision logic v1↔v2
│   └── Util/
│       ├── Logger.swift
│       ├── Clock.swift             # injectable clock for tests
│       └── Result+Retry.swift
└── WalkTalkTests/                  # XCTest target
    ├── Agent/
    │   ├── AgentRuntimeTests.swift
    │   ├── ProactiveQuotaTests.swift
    │   └── ToolRegistryTests.swift
    ├── Session/
    │   └── WalkSessionTests.swift
    ├── Keepsake/
    │   ├── ScriptGeneratorTests.swift
    │   ├── PosterComposerTests.swift
    │   └── KeepsakeFallbackTests.swift
    ├── Net/
    │   ├── LLMClientTests.swift
    │   └── AmapClientTests.swift
    └── Fixtures/
        ├── sample_track.json       # canned GPS for replay tests
        ├── sample_frames/          # canned image frames
        └── sample_dialog.json
```

Full leaf files appear inside their owning task. Engineer should not create any file not listed in a task.

---

## P0 — Assumption Spike

**Goal:** Drive every §9 unverified assumption to a written decision before a single line of production code is written. Output: 6 short markdown decision notes under `docs/superpowers/decisions/`, each ending with one of `confirmed`, `mitigation accepted`, or `architecture change required`.

**Time-box:** 1 calendar week. If an assumption cannot be resolved in its allotted day, escalate; do not slip silently.

**Why first:** Two of the six assumptions can invalidate the entire camera data flow (A1) or the demo (A3). Discover that in week 1, not week 9.

---

### Task P0-T0: Set up decisions directory and template

**Files:**
- Create: `docs/superpowers/decisions/_template.md`
- Create: `docs/superpowers/decisions/README.md`

- [ ] **Step 1: Create the template file**

```markdown
<!-- docs/superpowers/decisions/_template.md -->
# Decision: <short title>

**ID:** A<n> (matches spec §9)
**Date:** YYYY-MM-DD
**Status:** open | confirmed | mitigation accepted | architecture change required
**Owner:** <name>

## Question
<the §9 question verbatim>

## Investigation
<bullet list of what was tried, who was asked, links to docs/threads>

## Result
<what we found out>

## Decision
<one paragraph: what we will do, with rationale>

## Plan impact
<bullet list: which downstream tasks/files this affects, or "none">
```

- [ ] **Step 2: Create the index README**

```markdown
<!-- docs/superpowers/decisions/README.md -->
# Architecture decisions

Each decision corresponds to one item in spec §9 (`docs/superpowers/specs/2026-05-02-local-gravity-design.md`).

| ID | Title | Status |
|---|---|---|
| A1 | Insta360 preview-stream + onboard recording concurrency | open |
| A2 | Insta360 iOS SDK feature completeness | open |
| A3 | LLM endpoint reachability at demo venue | open |
| A4 | VLM model selection for outdoor scenes | open |
| A5 | TTS realtime: remote vs on-device | open |
| A6 | Background music / licensing | open |

A1 and A3 are blocking. The others are parallelizable.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/decisions/
git commit -m "docs: scaffold architecture decisions directory for P0 spike"
```

---

### Task P0-T1 (A1, BLOCKING): Verify Insta360 preview + onboard recording concurrency

**Files:**
- Create: `docs/superpowers/decisions/A1-camera-concurrency.md`
- Create: `spike/A1_camera_concurrency/README.md`
- Create: `spike/A1_camera_concurrency/notes.md`

**This is the highest-priority assumption.** If preview stream and on-camera recording cannot run concurrently, the entire CameraBridge design changes (we'd switch to "periodic snapshots + full recording" or time-slice the channel).

- [ ] **Step 1: Open the decision file in `open` status**

Copy `_template.md` to `A1-camera-concurrency.md`, fill ID/date/owner/question. Question text:

> Can the Insta360 camera (model in hand) sustain a WiFi P2P preview stream **while simultaneously** recording video to its onboard storage, for at least 30 continuous minutes, without one channel dropping the other?

- [ ] **Step 2: Reach out to Insta360 support**

Message the support team contact with this exact question:

> "对于 [具体型号]，能否同时进行（a）通过 WiFi 预览流向手机推送实时帧 和（b）相机本机录制完整视频？目标场景是 30 分钟散步全程并发。如不支持，是否有替代方案（如降帧率预览 / 周期性截图）能在录制期间获得相机视角？"

Capture the reply verbatim under `## Investigation` in the decision file.

- [ ] **Step 3: Empirical test (regardless of support answer)**

Open the official Insta360 sample app on the test phone:
- Connect camera over WiFi
- Start preview
- Start recording
- Walk for 5 minutes
- Stop recording
- Verify: preview stayed live AND recording produced a complete video file

Record results (video file exists, length, preview FPS observed) in `spike/A1_camera_concurrency/notes.md`.

- [ ] **Step 4: Reach a decision**

In the decision file, fill in `## Result`, `## Decision`, `## Plan impact`. Set status to one of:
- `confirmed` — both channels work, no plan changes
- `mitigation accepted` — works with caveats (e.g., reduced preview FPS); record the caveats
- `architecture change required` — list which P1/P3 tasks need rewriting

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/decisions/A1-camera-concurrency.md spike/
git commit -m "docs(A1): record camera concurrency decision"
```

---

### Task P0-T2 (A2): Verify Insta360 iOS SDK completeness

**Files:**
- Create: `docs/superpowers/decisions/A2-insta360-ios-sdk.md`

- [ ] **Step 1: Open decision file with question**

Question:

> Does the Insta360 iOS SDK (latest version) expose, in Swift or Objective-C with usable Swift interop: (1) WiFi pairing, (2) preview stream subscription as raw frames or H.264, (3) start/stop on-camera recording, (4) downloading a recorded video file from the camera to the phone, (5) reading current camera state? What is the minimum iOS deployment target?

- [ ] **Step 2: Inventory the SDK**

Pull the latest SDK from Insta360's developer resource center. For each of the 5 capabilities above, find the official method/class name and note it. If a capability is missing, mark it.

- [ ] **Step 3: Run the official sample on a real device**

Build and run the Insta360 sample iOS app on the test iPhone with the test camera. Confirm pairing, preview, recording, file download all work in the sample. Note any failures.

- [ ] **Step 4: Decide**

If all 5 capabilities work in the sample, status = `confirmed`. If anything is missing, status = `architecture change required` and list the workaround in `## Decision`.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/decisions/A2-insta360-ios-sdk.md
git commit -m "docs(A2): record Insta360 iOS SDK capability inventory"
```

---

### Task P0-T3 (A3, BLOCKING): Verify LLM endpoint reachability at demo venue

**Files:**
- Create: `docs/superpowers/decisions/A3-llm-endpoint-reachability.md`

The endpoint `http://100.99.139.20:18141` looks like a Tailscale / private network address. If the demo venue's network can't reach it, the demo dies.

- [ ] **Step 1: Open decision file with question**

Question:

> How will the demo phone reach `http://100.99.139.20:18141` from the venue WiFi or carrier network? Tailscale on the phone? A public reverse proxy? A backup endpoint?

- [ ] **Step 2: Test current reachability from a phone**

Install Tailscale on the test phone (or whatever VPN gives access to that 100.x address). Confirm `curl http://100.99.139.20:18141/v1/models` returns from the phone over LTE and over typical office WiFi.

- [ ] **Step 3: Plan the demo-day reachability path**

Pick one:
- **a)** Tailscale on demo phone, hotspot on demo phone — independent of venue WiFi.
- **b)** Public reverse proxy with auth (e.g., Cloudflare tunnel) so the endpoint becomes a public HTTPS URL.
- **c)** A second LLM endpoint (e.g., Azure OpenAI / Volcengine Ark) configured as backup; switch via build flag.

Recommend (a) + (c): primary is Tailscale on hotspot, backup is a public-internet model in case Tailscale fails.

- [ ] **Step 4: Decide and document**

Set status, fill `## Decision` with the chosen path and the exact env-var / config-toggle that swaps endpoints.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/decisions/A3-llm-endpoint-reachability.md
git commit -m "docs(A3): record LLM endpoint reachability strategy"
```

---

### Task P0-T4 (A4): Pick VLM model for outdoor scenes

**Files:**
- Create: `docs/superpowers/decisions/A4-vlm-model-selection.md`
- Create: `spike/A4_vlm_eval/eval.md`
- Create: `spike/A4_vlm_eval/images/` (5–10 outdoor photos: cherry blossom, sculpture, shopfront, lake view, etc.)

- [ ] **Step 1: Open decision file with question**

Question:

> Of the models available behind `http://100.99.139.20:18141`, which has the best vision capability for outdoor walking scenes (botany, sculpture, signage in Chinese, landscape)? Latency and cost matter; we will call it on every passive question (~1× per minute peak).

- [ ] **Step 2: List candidate models**

`curl http://100.99.139.20:18141/v1/models` and filter to vision-capable ones. Document the list in `eval.md`.

- [ ] **Step 3: Build a tiny eval set**

10 photos under `spike/A4_vlm_eval/images/`, each with a one-line "right answer" in `eval.md`. Take them yourself near 玄武湖 if possible.

- [ ] **Step 4: Run each candidate against the eval set**

```bash
# minimal shell script — run this for each model id
curl http://100.99.139.20:18141/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"<MODEL>\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"用一句话告诉我这张图里最显眼的事物是什么\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,$(base64 -w 0 image.jpg)\"}}]}]}"
```

Record latency (wall clock) and answer for each (model, image) pair.

- [ ] **Step 5: Decide**

Pick the model with best accuracy at ≤2s p50 latency. Document choice and runner-up (used as fallback). Set status to `confirmed`.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/decisions/A4-vlm-model-selection.md spike/A4_vlm_eval/
git commit -m "docs(A4): pick VLM model after eval"
```

---

### Task P0-T5 (A5): Decide TTS path — remote vs on-device

**Files:**
- Create: `docs/superpowers/decisions/A5-tts-path.md`

- [ ] **Step 1: Open decision file with question**

Question:

> Should we use the remote TTS exposed by the LLM endpoint (potentially better voice but adds 500ms–2s round-trip), or iOS `AVSpeechSynthesizer` (instant, free, but mechanical voice)? Or both with priority?

- [ ] **Step 2: Listen to both**

- Trigger `AVSpeechSynthesizer` in Xcode playground with a sample sentence in Chinese.
- Trigger remote TTS from `100.99.139.20:18141` (curl the audio endpoint per its OpenAI-compatible spec, e.g. `/v1/audio/speech`) for the same sentence.

Compare on phone speakers and Bluetooth headphones.

- [ ] **Step 3: Decide**

Recommendation: default = remote TTS for warmth; **fallback = `AVSpeechSynthesizer` whenever remote TTS exceeds 1.5s latency** (degrades gracefully). Document the latency threshold and the switching policy.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/decisions/A5-tts-path.md
git commit -m "docs(A5): pick TTS strategy with degradation threshold"
```

---

### Task P0-T6 (A6): Pick keepsake background music source

**Files:**
- Create: `docs/superpowers/decisions/A6-bgm.md`
- Create: `WalkTalk/Resources/bgm/` (placeholder; no files yet, just the directory + README)

- [ ] **Step 1: Open decision file with question**

Question:

> What background music plays under the keepsake video? Options: (a) curated royalty-free pack bundled in app, (b) iOS system sounds / Apple Music API (licensing concerns), (c) user picks from their library at export time, (d) no music — only ambient sound.

- [ ] **Step 2: Recommend (a) + later (c)**

For MVP: ship 5–8 royalty-free instrumental tracks (Pixabay / Free Music Archive / ccMixter) covering moods (calm, contemplative, upbeat). LLM script generator picks one based on walk's tone.

- [ ] **Step 3: Document choice**

Fill decision file. List the chosen source pack URL and license terms.

- [ ] **Step 4: Commit (just the decision; tracks downloaded in P5-T1)**

```bash
git add docs/superpowers/decisions/A6-bgm.md WalkTalk/Resources/bgm/.gitkeep
git commit -m "docs(A6): pick keepsake BGM source"
```

---

### Task P0-T7: Spike close-out — gate review

**Files:**
- Modify: `docs/superpowers/decisions/README.md` (update statuses)
- Create: `docs/superpowers/decisions/_spike-closeout.md`

- [ ] **Step 1: Update the index table**

In `README.md`, change every row's status to its final value.

- [ ] **Step 2: Write closeout note**

```markdown
<!-- docs/superpowers/decisions/_spike-closeout.md -->
# Spike closeout — YYYY-MM-DD

## Outcomes
- A1: <status>
- A2: <status>
- A3: <status>
- A4: <status>
- A5: <status>
- A6: <status>

## Plan changes triggered
<bullet list, e.g. "P1-T5 needs to use snapshot polling instead of preview stream because A1 came back as 'mitigation accepted'">

## Go / no-go
<go = continue to P1; no-go = re-brainstorm>
```

- [ ] **Step 3: If any decision changed plan tasks, edit those tasks now**

For each "Plan changes triggered" entry, open the affected task in this plan and mark the change inline with `<!-- A1 update YYYY-MM-DD: ... -->`. Do not silently rewrite — leave the audit trail.

- [ ] **Step 4: Commit and tag**

```bash
git add docs/superpowers/decisions/
git commit -m "docs: P0 spike closeout — go decision for P1"
git tag p0-closeout
```

---

**End of Batch 0 (P0 plan). After P0-T7 the repo has zero production code but has answered the questions that would otherwise wreck weeks of work.**

---

## P1 — Foundations (W1–W2)

**Goal:** Empty repo → an Xcode project that builds & runs on a real iPhone, with four independently-smoke-tested capability stubs:
1. `Insta360CameraBridge` — connects, gets one preview frame, starts/stops recording, downloads file.
2. `LocationSvc` — receives GPS updates while the screen is off.
3. `MapRenderer` — shows the basemap and draws a polyline.
4. `LLMClient` — completes one chat round-trip against `100.99.139.20:18141`.

Plus a minimal `RootView` with four buttons that exercise each. **No agent, no session logic, no UI polish.** Just: "the four pillars are alive."

**Pre-requisite:** P0 closed (especially A1, A2, A3).

---

### Task P1-T1: Create Xcode project and commit

**Files:**
- Create: `WalkTalk.xcodeproj/` (entire bundle)
- Create: `WalkTalk/App/WalkTalkApp.swift`
- Create: `WalkTalk/App/RootView.swift`
- Create: `WalkTalkTests/SmokeTests.swift`
- Create: `.xcode.env` (optional, for SwiftLint later)
- Modify: `.gitignore`

- [ ] **Step 1: Create the Xcode project**

In Xcode 15+:
- File → New → Project → iOS → App
- Product Name: `WalkTalk`
- Team: your Apple Developer team (must be set for real-device runs later)
- Organization Identifier: `com.<yourname>.walktalk`
- Interface: SwiftUI
- Language: Swift
- Storage: None
- Include Tests: ✅
- Save into the existing repo root (the `.xcodeproj` ends up at `walk-talk/WalkTalk.xcodeproj`)

- [ ] **Step 2: Set deployment target to iOS 17.0**

Xcode → project → WalkTalk target → General → Minimum Deployments → iOS 17.0.

- [ ] **Step 3: Replace `WalkTalkApp.swift` with the version below**

```swift
// WalkTalk/App/WalkTalkApp.swift
import SwiftUI

@main
struct WalkTalkApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 4: Create `RootView.swift` with four placeholder buttons**

```swift
// WalkTalk/App/RootView.swift
import SwiftUI

struct RootView: View {
    @State private var lastResult: String = "tap a button to smoke-test a pillar"

    var body: some View {
        VStack(spacing: 16) {
            Text("Local Gravity — pillars smoke test")
                .font(.headline)

            Button("1. Camera") { lastResult = "TODO P1-T3" }
            Button("2. Location") { lastResult = "TODO P1-T4" }
            Button("3. Map") { lastResult = "TODO P1-T5" }
            Button("4. LLM") { lastResult = "TODO P1-T6" }

            Divider()
            ScrollView {
                Text(lastResult)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}

#Preview { RootView() }
```

- [ ] **Step 5: Add a smoke unit test**

```swift
// WalkTalkTests/SmokeTests.swift
import XCTest
@testable import WalkTalk

final class SmokeTests: XCTestCase {
    func test_app_target_compiles() {
        XCTAssertTrue(true, "if this runs, the target builds")
    }
}
```

- [ ] **Step 6: Update `.gitignore`**

Append the standard Xcode ignores to existing `.gitignore`:

```gitignore
# Xcode
build/
DerivedData/
*.xcuserstate
xcuserdata/
*.xcscheme
!default.xcscheme
.swiftpm/
Package.resolved
*.hmap
*.ipa
*.dSYM.zip
*.dSYM
```

- [ ] **Step 7: Build and run on simulator**

```
Cmd+R in Xcode (target: any iPhone simulator on iOS 17)
```

Expected: app launches, RootView shows four buttons, tapping any prints `TODO P1-Tn`.

- [ ] **Step 8: Run the unit test**

```
Cmd+U in Xcode
```

Expected: `SmokeTests.test_app_target_compiles` passes.

- [ ] **Step 9: Commit**

```bash
git add WalkTalk.xcodeproj WalkTalk/ WalkTalkTests/ .gitignore
git commit -m "feat(p1): scaffold Xcode project with placeholder RootView"
```

---

### Task P1-T2: Add SDK dependencies

**Files:**
- Modify: `WalkTalk.xcodeproj/project.pbxproj` (via Xcode UI; do not hand-edit)
- Create: `docs/sdk-setup.md`

- [ ] **Step 1: Add 高德 iOS SDK**

Per 高德官方 iOS 接入文档(`https://lbs.amap.com/api/ios-sdk/guide/create-project/dev-attention`):
- Register an Amap developer account, create an iOS app, get an `AMapApiKey`.
- Add via Swift Package Manager (preferred): `https://github.com/amap-demo/amap-ios-sdk-spm` (or whatever the current official SPM mirror is — confirm in Amap docs).
- If SPM is not available, drop the `.framework` files into `WalkTalk/Frameworks/` and link them in target settings.
- Required modules: `AMapFoundation`, `MAMapKit`, `AMapSearchKit`.

Document the exact framework names and version pulled in `docs/sdk-setup.md`.

- [ ] **Step 2: Add Insta360 iOS SDK**

Per Insta360 developer resource center (`http://onlinemanual.insta360.com/developer/zh-cn/resource/sdk`):
- Download the iOS Camera SDK package.
- Add to project per its README. Most likely: drop `INSCameraSDK.framework` into `WalkTalk/Frameworks/`, add to target's "Frameworks, Libraries, and Embedded Content", set "Embed & Sign".
- LOOKUP: confirm the exact framework name(s) and any required dependencies (libstdc++, etc.) in the SDK README.

Document in `docs/sdk-setup.md`.

- [ ] **Step 3: Configure Info.plist permissions**

Add to `WalkTalk/Info.plist` (via Xcode UI's Info tab; create file if needed):

```
NSCameraUsageDescription          = "用于查看实时画面"  (often required by Insta360 SDK even though we use external camera)
NSMicrophoneUsageDescription      = "用于跟 AI 对话"
NSSpeechRecognitionUsageDescription = "用于把你说的话转成文字"
NSLocationWhenInUseUsageDescription = "用于记录散步轨迹"
NSLocationAlwaysAndWhenInUseUsageDescription = "用于在手机锁屏时继续记录散步轨迹"
NSLocalNetworkUsageDescription    = "用于连接影石相机的 WiFi 热点"
NSBonjourServices                 = ["_insta360._tcp", "_http._tcp"]   // LOOKUP exact services from SDK
```

Also enable Background Modes in Signing & Capabilities → "+ Capability" → Background Modes:
- ✅ Location updates
- ✅ Audio, AirPlay, and Picture in Picture (for STT/TTS in background)

- [ ] **Step 4: Build to confirm no link errors**

`Cmd+B` in Xcode. Expected: no errors. (Frameworks linked, even though no code uses them yet.)

- [ ] **Step 5: Commit**

```bash
git add WalkTalk.xcodeproj WalkTalk/Info.plist WalkTalk/Frameworks docs/sdk-setup.md
git commit -m "chore(p1): add Insta360 + Amap iOS SDKs and Info.plist permissions"
```

---

### Task P1-T3: Camera bridge skeleton — protocol + mock

**Files:**
- Create: `WalkTalk/Camera/CameraBridge.swift`
- Create: `WalkTalk/Camera/MockCameraBridge.swift`
- Create: `WalkTalkTests/Camera/CameraBridgeMockTests.swift`

We define the protocol and a mock first (TDD-friendly), then write the real bridge in P1-T4.

- [ ] **Step 1: Write the protocol**

```swift
// WalkTalk/Camera/CameraBridge.swift
import Foundation
import UIKit

public enum CameraBridgeError: Error, Equatable {
    case notConnected
    case alreadyRecording
    case notRecording
    case downloadFailed(String)
    case underlying(String)
}

/// Abstracts the Insta360 camera so production code can be unit-tested with mocks.
public protocol CameraBridge: AnyObject {
    /// True when the camera is paired and ready.
    var isConnected: Bool { get }

    /// Connect over WiFi. Throws on failure.
    func connect() async throws

    /// Subscribe to preview frames. The callback fires at ~1–2 fps with the latest sampled frame.
    /// Sampling rate and format are determined by the bridge implementation.
    func startPreviewStream(_ onFrame: @escaping (PreviewFrame) -> Void) throws

    /// Stop the preview stream.
    func stopPreviewStream()

    /// Begin on-camera recording. Throws if already recording.
    func startRecording() async throws

    /// Stop on-camera recording. Returns the resulting video file's identifier on the camera.
    @discardableResult
    func stopRecording() async throws -> CameraVideoHandle

    /// Download the recorded file from the camera to a local URL on the phone.
    func downloadVideo(_ handle: CameraVideoHandle, to localURL: URL) async throws
}

public struct PreviewFrame {
    public let image: UIImage
    public let capturedAt: Date
}

public struct CameraVideoHandle: Equatable {
    public let id: String          // SDK-defined file id on the camera
    public let approxDurationSec: Double
}
```

- [ ] **Step 2: Write the mock**

```swift
// WalkTalk/Camera/MockCameraBridge.swift
import Foundation
import UIKit

public final class MockCameraBridge: CameraBridge {
    public var isConnected: Bool = false
    public var connectShouldThrow: Bool = false
    public var recordingActive: Bool = false
    public var fakeVideoId: String = "mock-video-001"
    public var fakeVideoDuration: Double = 30.0

    private var frameTimer: Timer?
    private var onFrame: ((PreviewFrame) -> Void)?
    /// Supply a preloaded image for the mock to emit; if nil emits a 1x1 black image.
    public var stubFrameImage: UIImage?

    public init() {}

    public func connect() async throws {
        if connectShouldThrow { throw CameraBridgeError.underlying("mock connect failure") }
        isConnected = true
    }

    public func startPreviewStream(_ onFrame: @escaping (PreviewFrame) -> Void) throws {
        guard isConnected else { throw CameraBridgeError.notConnected }
        self.onFrame = onFrame
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let img = self.stubFrameImage ?? Self.blackPixel()
            self.onFrame?(PreviewFrame(image: img, capturedAt: Date()))
        }
    }

    public func stopPreviewStream() {
        frameTimer?.invalidate()
        frameTimer = nil
        onFrame = nil
    }

    public func startRecording() async throws {
        guard isConnected else { throw CameraBridgeError.notConnected }
        if recordingActive { throw CameraBridgeError.alreadyRecording }
        recordingActive = true
    }

    public func stopRecording() async throws -> CameraVideoHandle {
        guard recordingActive else { throw CameraBridgeError.notRecording }
        recordingActive = false
        return CameraVideoHandle(id: fakeVideoId, approxDurationSec: fakeVideoDuration)
    }

    public func downloadVideo(_ handle: CameraVideoHandle, to localURL: URL) async throws {
        // write 8 zero bytes so callers can check file existence
        try Data(repeating: 0, count: 8).write(to: localURL)
    }

    private static func blackPixel() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        UIColor.black.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
}
```

- [ ] **Step 3: Write the failing tests**

```swift
// WalkTalkTests/Camera/CameraBridgeMockTests.swift
import XCTest
@testable import WalkTalk

final class CameraBridgeMockTests: XCTestCase {
    func test_connect_setsIsConnectedTrue() async throws {
        let bridge = MockCameraBridge()
        try await bridge.connect()
        XCTAssertTrue(bridge.isConnected)
    }

    func test_startRecording_failsIfNotConnected() async {
        let bridge = MockCameraBridge()
        do {
            try await bridge.startRecording()
            XCTFail("should have thrown")
        } catch CameraBridgeError.notConnected {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_recording_lifecycle_returnsHandle() async throws {
        let bridge = MockCameraBridge()
        try await bridge.connect()
        try await bridge.startRecording()
        let handle = try await bridge.stopRecording()
        XCTAssertEqual(handle.id, "mock-video-001")
        XCTAssertEqual(handle.approxDurationSec, 30.0)
    }

    func test_downloadVideo_writesNonEmptyFile() async throws {
        let bridge = MockCameraBridge()
        try await bridge.connect()
        try await bridge.startRecording()
        let handle = try await bridge.stopRecording()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try await bridge.downloadVideo(handle, to: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attrs[.size] as? Int, 8)
    }
}
```

- [ ] **Step 4: Run tests**

```
Cmd+U
```

Expected: 4 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add WalkTalk/Camera WalkTalkTests/Camera
git commit -m "feat(p1): CameraBridge protocol + MockCameraBridge with tests"
```

---

### Task P1-T4: Insta360CameraBridge real implementation skeleton

**Files:**
- Create: `WalkTalk/Camera/Insta360CameraBridge.swift`

Because the Insta360 SDK API surface is not in my training set, this file is a structured skeleton with `LOOKUP:` markers. Each `LOOKUP` is a precise question to answer from the SDK's headers / docs / sample code. **Do not invent method names.** If a `LOOKUP` cannot be resolved, escalate; do not guess.

- [ ] **Step 1: Create the skeleton file**

```swift
// WalkTalk/Camera/Insta360CameraBridge.swift
import Foundation
import UIKit

// LOOKUP-1: import the actual Insta360 SDK module name. Examples possibly seen:
//   import INSCameraSDK
//   import InstaCameraSDK
// Confirm from the framework's umbrella header.
//
// import INSCameraSDK

public final class Insta360CameraBridge: CameraBridge {
    public private(set) var isConnected: Bool = false

    // LOOKUP-2: the SDK likely vends a singleton or manager (e.g. `INSCameraManager.shared()`).
    // Hold a reference to it here as a stored property.
    // private let sdk = INSCameraManager.shared()

    private var onFrame: ((PreviewFrame) -> Void)?
    private var currentRecordingId: String?

    public init() {}

    public func connect() async throws {
        // LOOKUP-3: connect API. Typically:
        //   - check WiFi SSID matches camera's broadcast (CHECK_WIFI)
        //   - call sdk.setupConnection(...) or similar
        //   - wait for delegate callback `onConnected` / `connectionDidEstablish`
        // Wrap the delegate-style callback into async via withCheckedThrowingContinuation.
        //
        // try await withCheckedThrowingContinuation { cont in
        //     sdk.setupConnection(success: { cont.resume() },
        //                        failure: { err in cont.resume(throwing: CameraBridgeError.underlying(err.localizedDescription)) })
        // }
        // self.isConnected = true
        throw CameraBridgeError.underlying("Insta360CameraBridge.connect not yet implemented — see LOOKUP-3")
    }

    public func startPreviewStream(_ onFrame: @escaping (PreviewFrame) -> Void) throws {
        guard isConnected else { throw CameraBridgeError.notConnected }
        self.onFrame = onFrame
        // LOOKUP-4: preview stream API. Typically:
        //   - start a streaming session (sdk.startPreviewStream(params))
        //   - register a delegate that receives raw frames or a player view
        //   - we want raw frames so we can feed them to VLM. If the SDK only exposes a player
        //     view, fall back to grabbing snapshots from that view periodically (per A1 mitigation).
        //
        // Per A1 spike outcome (see decisions/A1-camera-concurrency.md):
        //   - if confirmed, use full preview stream
        //   - if mitigation, use periodic snapshot polling (≤ 2 fps)
        //   - if architecture change, ... (decision file specifies the swap)
    }

    public func stopPreviewStream() {
        // LOOKUP-5: stop preview API
        onFrame = nil
    }

    public func startRecording() async throws {
        guard isConnected else { throw CameraBridgeError.notConnected }
        // LOOKUP-6: start recording API. Likely sdk.startRecording(options:completion:)
        //   - capture the resulting file id / handle into currentRecordingId
    }

    @discardableResult
    public func stopRecording() async throws -> CameraVideoHandle {
        // LOOKUP-7: stop recording API; SDK should return file metadata in the completion.
        guard let id = currentRecordingId else { throw CameraBridgeError.notRecording }
        defer { currentRecordingId = nil }
        // return CameraVideoHandle(id: id, approxDurationSec: <from SDK>)
        throw CameraBridgeError.underlying("Insta360CameraBridge.stopRecording not yet implemented — see LOOKUP-7")
    }

    public func downloadVideo(_ handle: CameraVideoHandle, to localURL: URL) async throws {
        // LOOKUP-8: download API. Usually sdk.downloadFile(fileId:to:progress:completion:)
        //   - return only after the file is fully on-phone
        //   - wrap progress into async via continuation
        throw CameraBridgeError.underlying("Insta360CameraBridge.downloadVideo not yet implemented — see LOOKUP-8")
    }
}
```

- [ ] **Step 2: Build (must compile even with all LOOKUPs unresolved)**

```
Cmd+B
```

Expected: build succeeds (the LOOKUPs are commented; the file just throws at runtime).

- [ ] **Step 3: Hook the Camera button in `RootView` to trigger a real connect**

Edit `RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    @State private var lastResult: String = "tap a button to smoke-test a pillar"
    private let camera = Insta360CameraBridge()

    var body: some View {
        VStack(spacing: 16) {
            Text("Local Gravity — pillars smoke test")
                .font(.headline)

            Button("1. Camera connect") {
                Task {
                    do {
                        try await camera.connect()
                        lastResult = "camera connected ✅"
                    } catch {
                        lastResult = "camera failed: \(error)"
                    }
                }
            }
            Button("2. Location") { lastResult = "TODO P1-T5" }
            Button("3. Map") { lastResult = "TODO P1-T6" }
            Button("4. LLM") { lastResult = "TODO P1-T7" }

            Divider()
            ScrollView {
                Text(lastResult)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 4: Run on real iPhone (not simulator) with camera powered on and connected over WiFi**

Tap "Camera connect". Expected (after LOOKUPs are filled in by the engineer): `camera connected ✅`.

If LOOKUPs not yet filled: expect the error string. **That is the explicit todo signal.**

- [ ] **Step 5: Commit**

```bash
git add WalkTalk/Camera/Insta360CameraBridge.swift WalkTalk/App/RootView.swift
git commit -m "feat(p1): Insta360CameraBridge skeleton with LOOKUP markers"
```

---

### Task P1-T5: LocationSvc — CoreLocation wrapper

**Files:**
- Create: `WalkTalk/Location/LocationSvc.swift`
- Create: `WalkTalk/Location/TrackBuffer.swift`
- Create: `WalkTalkTests/Location/TrackBufferTests.swift`

- [ ] **Step 1: Write `TrackBuffer` (pure logic, fully testable)**

```swift
// WalkTalk/Location/TrackBuffer.swift
import Foundation
import CoreLocation

public struct TrackPoint: Equatable {
    public let coordinate: CLLocationCoordinate2D
    public let timestamp: Date
    public let horizontalAccuracy: Double
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

/// Holds a rolling 30-minute buffer of GPS points. Thread-safe via a serial queue.
public final class TrackBuffer {
    private let retention: TimeInterval
    private var points: [TrackPoint] = []
    private let queue = DispatchQueue(label: "TrackBuffer")

    public init(retention: TimeInterval = 30 * 60) {
        self.retention = retention
    }

    public func append(_ p: TrackPoint, now: Date = Date()) {
        queue.sync {
            points.append(p)
            let cutoff = now.addingTimeInterval(-retention)
            points.removeAll { $0.timestamp < cutoff }
        }
    }

    public var count: Int { queue.sync { points.count } }
    public var snapshot: [TrackPoint] { queue.sync { points } }

    /// Returns the GPS reading closest to the given timestamp (within tolerance), or nil.
    public func nearest(to t: Date, tolerance: TimeInterval = 5) -> TrackPoint? {
        queue.sync {
            points.min(by: { abs($0.timestamp.timeIntervalSince(t)) < abs($1.timestamp.timeIntervalSince(t)) })
                .flatMap { abs($0.timestamp.timeIntervalSince(t)) <= tolerance ? $0 : nil }
        }
    }

    public func clear() { queue.sync { points.removeAll() } }
}
```

- [ ] **Step 2: Write the tests**

```swift
// WalkTalkTests/Location/TrackBufferTests.swift
import XCTest
import CoreLocation
@testable import WalkTalk

final class TrackBufferTests: XCTestCase {
    private func p(_ lat: Double, _ lng: Double, _ t: Date) -> TrackPoint {
        TrackPoint(coordinate: .init(latitude: lat, longitude: lng), timestamp: t, horizontalAccuracy: 5)
    }

    func test_append_storesPoints() {
        let buf = TrackBuffer()
        buf.append(p(0, 0, Date()))
        XCTAssertEqual(buf.count, 1)
    }

    func test_evictsOlderThanRetention() {
        let buf = TrackBuffer(retention: 60)
        let now = Date()
        buf.append(p(0, 0, now.addingTimeInterval(-120)), now: now)
        buf.append(p(1, 1, now), now: now)
        XCTAssertEqual(buf.count, 1)
        XCTAssertEqual(buf.snapshot.first?.coordinate.latitude, 1)
    }

    func test_nearest_returnsClosestWithinTolerance() {
        let buf = TrackBuffer()
        let base = Date()
        buf.append(p(0, 0, base))
        buf.append(p(1, 1, base.addingTimeInterval(10)))
        let hit = buf.nearest(to: base.addingTimeInterval(2), tolerance: 5)
        XCTAssertEqual(hit?.coordinate.latitude, 0)
    }

    func test_nearest_nilWhenOutsideTolerance() {
        let buf = TrackBuffer()
        let base = Date()
        buf.append(p(0, 0, base))
        XCTAssertNil(buf.nearest(to: base.addingTimeInterval(60), tolerance: 5))
    }
}
```

- [ ] **Step 3: Run tests — they should pass**

```
Cmd+U → only TrackBufferTests
```

- [ ] **Step 4: Write `LocationSvc`**

```swift
// WalkTalk/Location/LocationSvc.swift
import Foundation
import CoreLocation

public final class LocationSvc: NSObject, CLLocationManagerDelegate {
    public let buffer: TrackBuffer
    private let manager: CLLocationManager

    public init(buffer: TrackBuffer = TrackBuffer()) {
        self.buffer = buffer
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5            // meters
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .fitness
    }

    public func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    public func start() {
        manager.startUpdatingLocation()
    }

    public func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            buffer.append(TrackPoint(
                coordinate: loc.coordinate,
                timestamp: loc.timestamp,
                horizontalAccuracy: loc.horizontalAccuracy
            ))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // P1: just log. Production path handled in P3-T5.
        print("LocationSvc error: \(error)")
    }
}
```

- [ ] **Step 5: Wire to RootView "Location" button**

Replace the `2. Location` button in RootView:

```swift
@StateObject private var locationModel = LocationModel()

Button("2. Location start") {
    locationModel.start { msg in lastResult = msg }
}
```

Add at the bottom of `RootView.swift`:

```swift
import Combine

final class LocationModel: ObservableObject {
    let svc = LocationSvc()
    func start(_ onUpdate: @escaping (String) -> Void) {
        svc.requestPermission()
        svc.start()
        // Poll the buffer every second for first 5 sec to show life signs.
        Task {
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let n = svc.buffer.count
                let last = svc.buffer.snapshot.last
                await MainActor.run {
                    if let p = last {
                        onUpdate("\(n) points; last: \(p.coordinate.latitude), \(p.coordinate.longitude)")
                    } else {
                        onUpdate("\(n) points; waiting…")
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 6: Run on real device, walk a few steps**

Expected: text shows growing point count and a coordinate.

- [ ] **Step 7: Commit**

```bash
git add WalkTalk/Location WalkTalkTests/Location WalkTalk/App/RootView.swift
git commit -m "feat(p1): LocationSvc + TrackBuffer with tests, smoke-tested via RootView"
```

---

### Task P1-T6: MapRenderer — basemap + polyline

**Files:**
- Create: `WalkTalk/Map/MapRenderer.swift`
- Create: `WalkTalk/Map/MapPreviewView.swift`

The 高德 iOS SDK exposes `MAMapView`. We wrap it in a SwiftUI `UIViewRepresentable`.

- [ ] **Step 1: Initialize 高德 SDK with API key**

In `WalkTalkApp.swift`, add init:

```swift
import SwiftUI
// LOOKUP-AMAP-1: confirm import names in 高德 iOS SDK install guide
// import AMapFoundationKit

@main
struct WalkTalkApp: App {
    init() {
        // LOOKUP-AMAP-2: the canonical key registration call. As of recent SDKs:
        //   AMapServices.shared().apiKey = "<your key>"
        //   AMapServices.shared().enableHTTPS = true
        // Confirm in the SDK's getting-started doc and replace below.
        // AMapServices.shared().apiKey = "REPLACE_WITH_YOUR_KEY"
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
```

Store the key in a config (do NOT commit the real key):

Create `WalkTalk/Resources/Secrets.example.plist` (committed):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>AMapApiKey</key><string>YOUR_KEY_HERE</string>
    <key>LLMEndpoint</key><string>http://100.99.139.20:18141</string>
    <key>LLMApiKey</key><string>YOUR_OPENAI_COMPATIBLE_KEY</string>
</dict>
</plist>
```

Add `WalkTalk/Resources/Secrets.plist` to `.gitignore` (real one, populated by engineer).

- [ ] **Step 2: Create the `MapPreviewView` SwiftUI wrapper**

```swift
// WalkTalk/Map/MapPreviewView.swift
import SwiftUI
// LOOKUP-AMAP-3: import MAMapKit

public struct MapPreviewView: UIViewRepresentable {
    public let track: [CLLocationCoordinate2D]
    public init(track: [CLLocationCoordinate2D]) { self.track = track }

    public func makeUIView(context: Context) -> UIView {
        // LOOKUP-AMAP-4: instantiate MAMapView, set delegate, return it.
        // let v = MAMapView(frame: .zero)
        // v.showsUserLocation = false
        // return v
        return UIView()  // placeholder until LOOKUP filled
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        // LOOKUP-AMAP-5: convert track → MAPolyline, remove old overlays, add new.
        // guard let mapView = uiView as? MAMapView else { return }
        // mapView.removeOverlays(mapView.overlays ?? [])
        // let coords = track
        // let line = MAPolyline(coordinates: coords, count: UInt(coords.count))
        // mapView.add(line)
    }
}
```

- [ ] **Step 3: Create `MapRenderer` (thin facade for now; expanded in P4)**

```swift
// WalkTalk/Map/MapRenderer.swift
import Foundation
import CoreLocation
import UIKit

public final class MapRenderer {
    public init() {}

    /// Render the given track to a static UIImage of the given size. Used by KeepsakeBuilder.
    /// In P1 this is a stub returning a 100x100 blue square; P4-T2 implements the real render.
    public func renderStatic(track: [CLLocationCoordinate2D], size: CGSize) async throws -> UIImage {
        UIGraphicsBeginImageContext(size)
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
}
```

- [ ] **Step 4: Wire RootView "3. Map" button to push a temporary map screen**

Add a sheet that hosts `MapPreviewView` with a fake 3-point track.

```swift
@State private var showMap = false
...
Button("3. Map preview") { showMap = true }
    .sheet(isPresented: $showMap) {
        MapPreviewView(track: [
            .init(latitude: 32.072, longitude: 118.794),
            .init(latitude: 32.074, longitude: 118.796),
            .init(latitude: 32.076, longitude: 118.797),
        ])
    }
```

- [ ] **Step 5: Run on device with API key configured**

Expected: a sheet shows 高德 basemap with a polyline near 玄武湖. (Until LOOKUP-AMAP-* are filled, you'll see a blank UIView; that's the explicit todo.)

- [ ] **Step 6: Commit**

```bash
git add WalkTalk/Map WalkTalk/App WalkTalk/Resources/Secrets.example.plist .gitignore
git commit -m "feat(p1): MapRenderer + MapPreviewView with Amap LOOKUP markers"
```

---

### Task P1-T7: LLMClient — OpenAI-compatible chat round-trip

**Files:**
- Create: `WalkTalk/Net/LLMClient.swift`
- Create: `WalkTalk/Net/Secrets.swift`
- Create: `WalkTalkTests/Net/LLMClientTests.swift`

- [ ] **Step 1: Secrets loader**

```swift
// WalkTalk/Net/Secrets.swift
import Foundation

public struct Secrets {
    public let amapApiKey: String
    public let llmEndpoint: URL
    public let llmApiKey: String

    public static let shared: Secrets = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let amap = plist["AMapApiKey"],
              let endpoint = plist["LLMEndpoint"].flatMap(URL.init(string:)),
              let llmKey = plist["LLMApiKey"]
        else {
            fatalError("Secrets.plist missing or malformed — copy Secrets.example.plist and fill it in")
        }
        return Secrets(amapApiKey: amap, llmEndpoint: endpoint, llmApiKey: llmKey)
    }()

    private init(amapApiKey: String, llmEndpoint: URL, llmApiKey: String) {
        self.amapApiKey = amapApiKey
        self.llmEndpoint = llmEndpoint
        self.llmApiKey = llmApiKey
    }
}
```

- [ ] **Step 2: LLMClient — minimal chat completion**

```swift
// WalkTalk/Net/LLMClient.swift
import Foundation

public struct ChatMessage: Codable, Equatable {
    public let role: String   // "system" | "user" | "assistant" | "tool"
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct ChatRequest: Codable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public init(model: String, messages: [ChatMessage], temperature: Double? = nil) {
        self.model = model; self.messages = messages; self.temperature = temperature
    }
}

public struct ChatResponse: Codable {
    public struct Choice: Codable { public let message: ChatMessage }
    public let choices: [Choice]
}

public final class LLMClient {
    private let endpoint: URL
    private let apiKey: String
    private let session: URLSession

    public init(endpoint: URL = Secrets.shared.llmEndpoint,
                apiKey: String = Secrets.shared.llmApiKey,
                session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    public func chat(_ request: ChatRequest) async throws -> ChatResponse {
        var url = endpoint
        url.append(path: "/v1/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMClientError.http((response as? HTTPURLResponse)?.statusCode ?? -1, body)
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }
}

public enum LLMClientError: Error, Equatable {
    case http(Int, String)
}
```

- [ ] **Step 3: Test against a stub `URLProtocol`**

```swift
// WalkTalkTests/Net/LLMClientTests.swift
import XCTest
@testable import WalkTalk

final class StubURLProtocol: URLProtocol {
    static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let r = Self.responder?(request) else { return }
        client?.urlProtocol(self, didReceive: r.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class LLMClientTests: XCTestCase {
    private func makeClient(_ json: String) -> LLMClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, json.data(using: .utf8)!)
        }
        return LLMClient(endpoint: URL(string: "http://stub.example/v1")!,
                         apiKey: "stub",
                         session: URLSession(configuration: cfg))
    }

    func test_chat_decodesAssistantMessage() async throws {
        let client = makeClient(#"{"choices":[{"message":{"role":"assistant","content":"hi"}}]}"#)
        let resp = try await client.chat(ChatRequest(
            model: "test", messages: [ChatMessage(role: "user", content: "ping")]
        ))
        XCTAssertEqual(resp.choices.first?.message.content, "hi")
    }

    func test_chat_throwsOnHttpError() async {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.responder = { req in
            let r = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (r, "boom".data(using: .utf8)!)
        }
        let client = LLMClient(endpoint: URL(string: "http://stub.example/v1")!,
                               apiKey: "stub",
                               session: URLSession(configuration: cfg))
        do {
            _ = try await client.chat(ChatRequest(model: "m", messages: []))
            XCTFail("should have thrown")
        } catch LLMClientError.http(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
```

- [ ] **Step 4: Run tests**

`Cmd+U`. Expected: 2 new tests pass.

- [ ] **Step 5: Wire RootView "4. LLM" button to live endpoint**

```swift
Button("4. LLM ping") {
    Task {
        do {
            let resp = try await LLMClient().chat(ChatRequest(
                model: "REPLACE_WITH_MODEL_FROM_A4",        // from decisions/A4
                messages: [ChatMessage(role: "user", content: "用一个字回应：到")]
            ))
            lastResult = "LLM: \(resp.choices.first?.message.content ?? "<empty>")"
        } catch {
            lastResult = "LLM failed: \(error)"
        }
    }
}
```

- [ ] **Step 6: Run on device with Tailscale (or whatever A3 chose) active**

Tap "LLM ping". Expected: assistant reply within 2s.

- [ ] **Step 7: Commit**

```bash
git add WalkTalk/Net WalkTalkTests/Net WalkTalk/App/RootView.swift
git commit -m "feat(p1): LLMClient with chat round-trip and stubbed unit tests"
```

---

### Task P1-T8: AmapClient — REST wrapper for the 4 search APIs

**Files:**
- Create: `WalkTalk/Net/AmapClient.swift`
- Create: `WalkTalkTests/Net/AmapClientTests.swift`

We use the Amap Web Service REST APIs (not just the iOS SDK's `AMapSearch`) because (a) we already have HTTP plumbing, (b) the REST responses are easier to mock in tests, (c) the iOS `AMapSearch` SDK is delegate-based and harder to wrap.

API reference: `https://lbs.amap.com/api/webservice/guide/api/search`.

- [ ] **Step 1: Define the response types**

```swift
// WalkTalk/Net/AmapClient.swift
import Foundation
import CoreLocation

public struct AmapPOI: Equatable {
    public let id: String
    public let name: String
    public let type: String
    public let address: String
    public let coordinate: CLLocationCoordinate2D
    public let distanceMeters: Int?
}

public enum AmapClientError: Error, Equatable {
    case http(Int, String)
    case apiStatus(String, String)   // (status, info)
    case decoding(String)
}

public final class AmapClient {
    private let baseURL = URL(string: "https://restapi.amap.com")!
    private let key: String
    private let session: URLSession

    public init(key: String = Secrets.shared.amapApiKey, session: URLSession = .shared) {
        self.key = key; self.session = session
    }

    public func aroundSearch(lat: Double, lng: Double,
                             keyword: String? = nil,
                             types: String? = nil,
                             radius: Int = 1000,
                             pageSize: Int = 10) async throws -> [AmapPOI] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v3/place/around"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "location", value: "\(lng),\(lat)"),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "offset", value: String(pageSize)),
            URLQueryItem(name: "extensions", value: "base"),
        ]
        if let keyword { comps.queryItems?.append(URLQueryItem(name: "keywords", value: keyword)) }
        if let types { comps.queryItems?.append(URLQueryItem(name: "types", value: types)) }

        return try await fetchPOIs(url: comps.url!)
    }

    public func textSearch(query: String, region: String? = nil) async throws -> [AmapPOI] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v3/place/text"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "extensions", value: "base"),
        ]
        if let region { comps.queryItems?.append(URLQueryItem(name: "city", value: region)) }
        return try await fetchPOIs(url: comps.url!)
    }

    public struct WalkingDirection: Equatable {
        public let distanceMeters: Int
        public let durationSeconds: Int
        public let bearingFromOrigin: Double   // degrees, 0=N
    }

    public func walkingDirection(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> WalkingDirection {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v3/direction/walking"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "origin", value: "\(from.longitude),\(from.latitude)"),
            URLQueryItem(name: "destination", value: "\(to.longitude),\(to.latitude)"),
        ]
        let data = try await fetchRaw(comps.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String, status == "1",
              let route = json["route"] as? [String: Any],
              let paths = route["paths"] as? [[String: Any]],
              let first = paths.first,
              let dStr = first["distance"] as? String, let d = Int(dStr),
              let tStr = first["duration"] as? String, let t = Int(tStr)
        else { throw AmapClientError.decoding("walking shape unexpected") }

        let bearing = Self.bearing(from: from, to: to)
        return WalkingDirection(distanceMeters: d, durationSeconds: t, bearingFromOrigin: bearing)
    }

    public struct GeoResult: Equatable {
        public let formattedAddress: String
        public let coordinate: CLLocationCoordinate2D
    }

    public func reverseGeocode(_ c: CLLocationCoordinate2D) async throws -> GeoResult {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v3/geocode/regeo"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "location", value: "\(c.longitude),\(c.latitude)"),
        ]
        let data = try await fetchRaw(comps.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String, status == "1",
              let regeo = json["regeocode"] as? [String: Any],
              let addr = regeo["formatted_address"] as? String
        else { throw AmapClientError.decoding("regeo shape unexpected") }
        return GeoResult(formattedAddress: addr, coordinate: c)
    }

    // MARK: - shared

    private func fetchRaw(_ url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AmapClientError.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                                       String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func fetchPOIs(url: URL) async throws -> [AmapPOI] {
        let data = try await fetchRaw(url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AmapClientError.decoding("not a json object")
        }
        if let status = json["status"] as? String, status != "1" {
            let info = json["info"] as? String ?? ""
            throw AmapClientError.apiStatus(status, info)
        }
        guard let arr = json["pois"] as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let loc = dict["location"] as? String
            else { return nil }
            let parts = loc.split(separator: ",")
            guard parts.count == 2,
                  let lng = Double(parts[0]),
                  let lat = Double(parts[1])
            else { return nil }
            let dist: Int? = (dict["distance"] as? String).flatMap(Int.init)
            return AmapPOI(
                id: id, name: name,
                type: dict["type"] as? String ?? "",
                address: dict["address"] as? String ?? "",
                coordinate: .init(latitude: lat, longitude: lng),
                distanceMeters: dist
            )
        }
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}
```

- [ ] **Step 2: Tests with stub responses**

```swift
// WalkTalkTests/Net/AmapClientTests.swift
import XCTest
@testable import WalkTalk

final class AmapClientTests: XCTestCase {
    private func makeClient(json: String) -> AmapClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.responder = { req in
            let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r, json.data(using: .utf8)!)
        }
        return AmapClient(key: "k", session: URLSession(configuration: cfg))
    }

    func test_aroundSearch_parsesPois() async throws {
        let client = makeClient(json: #"""
        {"status":"1","pois":[
          {"id":"abc","name":"老茶馆","type":"美食","location":"118.794,32.072","distance":"123","address":"南京市"}
        ]}
        """#)
        let result = try await client.aroundSearch(lat: 32.072, lng: 118.794)
        XCTAssertEqual(result.first?.name, "老茶馆")
        XCTAssertEqual(result.first?.distanceMeters, 123)
    }

    func test_aroundSearch_throwsOnApiStatus() async {
        let client = makeClient(json: #"{"status":"0","info":"INVALID_KEY"}"#)
        do {
            _ = try await client.aroundSearch(lat: 0, lng: 0)
            XCTFail("should have thrown")
        } catch AmapClientError.apiStatus(let s, let info) {
            XCTAssertEqual(s, "0"); XCTAssertEqual(info, "INVALID_KEY")
        } catch { XCTFail("wrong error: \(error)") }
    }
}
```

- [ ] **Step 3: Run tests**

`Cmd+U` — both pass.

- [ ] **Step 4: Commit**

```bash
git add WalkTalk/Net/AmapClient.swift WalkTalkTests/Net/AmapClientTests.swift
git commit -m "feat(p1): AmapClient REST wrapper for around/text/walking/regeo"
```

---

### Task P1-T9: P1 close-out

**Files:**
- Create: `docs/superpowers/plans/checkpoints/P1-closeout.md`

- [ ] **Step 1: Run full test suite**

`Cmd+U` on the whole `WalkTalkTests` target. Expected: all green.

- [ ] **Step 2: Manual smoke on real device — checklist**

Tap each RootView button. Expect:
- Camera connect: ✅ (or known error if LOOKUP-* not yet filled by engineer)
- Location start: ✅ growing point count
- Map preview: ✅ basemap + polyline near 玄武湖
- LLM ping: ✅ assistant reply

- [ ] **Step 3: Write the checkpoint note**

```markdown
# P1 close-out

**Date:** YYYY-MM-DD
**All unit tests:** <count> passing
**On-device smoke results:**
- Camera: <pass/fail/lookup-pending>
- Location: <pass/fail>
- Map: <pass/fail/lookup-pending>
- LLM: <pass/fail>

**LOOKUPs still open:** <list>
**Known issues going into P2:** <list>
```

- [ ] **Step 4: Commit and tag**

```bash
git add docs/superpowers/plans/checkpoints/P1-closeout.md
git commit -m "docs(p1): close-out checkpoint"
git tag p1-done
```

---

**End of Batch 1 (P1 Foundations).**

