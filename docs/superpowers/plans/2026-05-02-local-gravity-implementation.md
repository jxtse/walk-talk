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
