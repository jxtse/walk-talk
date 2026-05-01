<!-- docs/superpowers/decisions/_spike-closeout.md -->
# Spike closeout — 2026-05-02

## Outcomes
- A1 (Insta360 preview + recording concurrency): **open / provisional** — no hardware available in this spike session. Provisional design assumption is "mitigation accepted" so downstream planning can proceed against an agnostic frame-source interface. Owner of the test rig must run the empirical 5-min walk test by 2026-05-09.
- A2 (Insta360 iOS SDK completeness): **open / provisional** — no Xcode + no SDK access in this spike session. Plan continues to use a 5-method protocol-first wrapper. SDK inventory + sample-app run owed by 2026-05-09.
- A3 (LLM endpoint reachability): **mitigation accepted** — endpoint is on a Tailscale tailnet (100.99.139.20:18141), confirmed reachable + OpenAI-compatible from a tailnet host (~0.76 s for `/v1/models`). Demo path = Tailscale on iPhone + LTE hotspot, with a public-internet OpenAI-compatible backup endpoint configured via `LG_LLM_BASE_URL` / `LG_LLM_API_KEY` env vars. iPhone-over-LTE re-test required at T-7 days before any public demo.
- A4 (VLM model selection): **confirmed** — primary `gpt-4o` (~2.5 s p50), fallback `gpt-4.1`. Smoke-tested with one public-domain landscape JPEG; got correct, idiomatic Chinese answers from both. Discovered endpoint quirk: data-URL prefix must claim `image/png` regardless of actual bytes — encoded into the LLMClient design. Real outdoor eval set still owed before P3 ships.
- A5 (TTS realtime): **mitigation accepted** — the LLM router does NOT expose any of the standard TTS paths (all 5 probes returned 404). Default ships as `AVSpeechSynthesizer` (with enhanced zh-CN voice required by pre-flight). RemoteTTS code path stays as a stub awaiting a confirmed remote endpoint URL (ask endpoint owner; or evaluate Azure Speech 神经语音 by 2026-05-16). Circuit-breaker policy: drop to local if any remote call exceeds 1.5 s wall-clock, and force local for 60 s after.
- A6 (Background music): **confirmed** — Pixabay Music (commercial-OK, no attribution) primary, Free Music Archive CC0/CC-BY secondary. Apple Music API permanently rejected for MVP (DRM + license blocks export). 7-mood matrix defined (calm / contemplative / upbeat / wistful / playful / cinematic / ambient_nature). Track files + LICENSES.md ledger owed in P5-T1.

## Plan changes triggered

- **P1-T2 / P1-T3 (LLMClient):**
  - Default model = `gpt-4o` (replaces every `REPLACE_WITH_MODEL_FROM_A4` and `REPLACE_WITH_VISION_MODEL_FROM_A4` placeholder in the plan, including lines ~1555, ~3086, ~3932, ~3945).
  - Image content payload must claim `data:image/png;base64,` prefix regardless of source bytes (endpoint quirk; see A4).
  - Read both `LG_LLM_BASE_URL` and `LG_LLM_API_KEY` from env / Info.plist; send `Authorization: Bearer ...` header only when API key is non-empty (tailnet path is auth-less).

- **P1-T5 (CameraBridge skeleton):**
  - Author the consumer interface as `previewFrames: AsyncStream<CVPixelBuffer>` and ensure the implementation can switch between (a) live H.264 preview stream and (b) snapshot polling (~0.2–0.5 fps) at runtime. Existing inline `// Per A1 spike outcome` comment around plan line 927 still applies — leave it.

- **P1-T6 (InstaCameraSDK protocol):**
  - Keep the 5-method protocol; implementation bodies remain stubs until A2 closes (no later than 2026-05-09). No code that actually calls the SDK should be merged before then.

- **P3-T? (TTSService, plan lines ~3469, ~3559, ~3652):**
  - Default `selection = .local` (`AVSpeechSynthesizer`). `RemoteTTS` ships as a stub returning "not configured" until `LG_REMOTE_TTS_BASE_URL` env var is set. Add 1.5 s circuit breaker + 60 s forced-local penalty.

- **P5-T1 (BGM bundling):**
  - Source 5–8 tracks from Pixabay Music per the mood matrix in `A6-bgm.md`. Write `WalkTalk/Resources/bgm/LICENSES.md` ledger alongside the audio files.
  - LLM keepsake-script prompt must emit a `mood` field constrained to the 7-tag closed vocabulary.

- **Demo runbook (whichever batch owns it):**
  - Add T-7 day dry-run: `curl /v1/models` from demo iPhone over LTE, must succeed in <2 s.
  - Add T-1 day dry-run: same test on demo-venue WiFi if accessible.
  - Add T-0 pre-flight: Tailscale "Always-on VPN" enabled; enhanced zh-CN voice (Yunyang/Tingting) downloaded under Settings → Accessibility; speakers test sentence at venue ambient noise level.
  - Add "first-call warm-up" — one VLM call with a dummy image to prime caches before walk start.
  - Add explicit camera concurrency check: "preview survived recording for full 30-minute walk in dry-run".

- **Audit-trail comments to add into the plan file:** for each of the bullets above whose changes affect a specific task in `docs/superpowers/plans/2026-05-02-local-gravity-implementation.md`, add an inline `<!-- A<n> update 2026-05-02: ... -->` marker on the affected task. **Not done in this commit** because the constraint forbids touching files outside `docs/superpowers/decisions/`. The owner who picks up P1 should make these edits as a first step.

## Go / no-go

**Conditional GO** to begin P1 (foundations / scaffolding).

Justification:
- A3, A4, A6 are settled enough to author the LLMClient, default model selection, and BGM design without speculation.
- A5 is settled enough to ship the TTS protocol with a working default (`AVSpeechSynthesizer`).
- A1 and A2 remain provisional but the plan's protocol-first / interface-agnostic design isolates the unknowns. P1 work that does NOT depend on the Insta360 SDK can proceed in parallel; any task that *does* call into the SDK (P1-T6 implementation, P3 walk loop's camera tap) must remain stubbed until A1/A2 close empirically.

**Hard gate before P3 / P4 ship:** A1 and A2 must reach `confirmed` or `mitigation accepted` (with documented mitigation). If either is still `open` on 2026-05-09, escalate and re-plan.
