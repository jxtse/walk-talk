# Decision: TTS path — remote vs on-device

**ID:** A5 (matches spec §9)
**Date:** 2026-05-02
**Status:** mitigation accepted (default `AVSpeechSynthesizer`; remote TTS deferred until a working endpoint is identified — revisit no later than 2026-05-16)
**Owner:** unassigned

## Question
Should we use the remote TTS exposed by the LLM endpoint (potentially better voice but adds 500 ms–2 s round-trip), or iOS `AVSpeechSynthesizer` (instant, free, but mechanical voice)? Or both with priority?

## Investigation
- Remote TTS endpoint probe on `http://100.99.139.20:18141`:
  ```
  POST /v1/audio/speech    → HTTP 404 Not Found
  POST /v1/audio/synthesize → HTTP 404
  POST /audio/speech       → HTTP 404
  POST /tts                → HTTP 404
  POST /v1/tts             → HTTP 404
  ```
  None of the standard OpenAI-style or community-style TTS routes are exposed by this router. `/v1/models` listing contains zero models with TTS in the ID; only `text-embedding-*`, chat models, and search agents.
  **Conclusion: the LLM router at `100.99.139.20:18141` does not currently expose a TTS endpoint that we can reach.** Whether one exists at a different port or an undocumented path is unknown. Owner of the endpoint must be asked.

- iOS `AVSpeechSynthesizer`:
  - Available offline, zero-latency for "begin speaking", supports zh-CN / zh-TW voices.
  - Voice quality: mechanical but intelligible. iOS 16+ ships "enhanced" Chinese voices (Tingting, Sinji) that are noticeably better than the legacy ones; download requires manual user step under Settings → Accessibility → Spoken Content → Voices.
  - **Not auditioned in this session** (no iPhone available).

- Alternative remote TTS providers we could plug in instead:
  - Volcengine (火山引擎) TTS — Mandarin native, sub-second latency, paid.
  - Azure Speech (神经语音) — Mandarin "Xiaoxiao", "Yunyang" — sub-second latency, paid, the de-facto best Chinese TTS.
  - ElevenLabs / OpenAI `tts-1-hd` — public internet, requires API key, English-leaning.
  - Local on-device alternatives beyond AVSpeechSynthesizer: bundled CoreML voices (e.g., StyleTTS2 quantized) — significant binary size cost, complex.

## Result
- Cannot rely on the existing tailnet endpoint for TTS today; it returns 404 on every probed path.
- `AVSpeechSynthesizer` is the only zero-effort path that is **guaranteed** to work for the demo.
- A "remote TTS for warmth + AVSpeechSynthesizer fallback" architecture remains desirable, but we need a confirmed remote endpoint first.

## Decision (mitigation accepted)
**MVP/demo path:** ship with `AVSpeechSynthesizer` as the **default** TTS implementation. Pre-flight checklist forces the user to enable an "enhanced" Chinese voice on the demo iPhone, gaining the better of the two on-device options for free.

**Wrapper architecture (still as planned):** `TTSService` is a protocol with two concrete impls — `LocalTTS` (AVSpeechSynthesizer) and `RemoteTTS` (HTTP). Both are wired in the app. The selection policy:

```
preferred = .local                             // default for now
if RemoteTTSEndpoint.isConfigured && lastRemoteLatencyP50 < 1.5s {
    preferred = .remote
}
```

When the policy chooses remote and a single call exceeds **1.5 s** wall-clock, the result is dropped and the same text is spoken via `LocalTTS` instead, *and* the next 60 s of calls are forced to local (circuit breaker).

**Latency threshold:** 1.5 s (call-start to first audio byte). Beyond this, the conversational rhythm of the walk loop breaks.

**To unlock remote TTS later:**
1. Ask the endpoint owner (or check internal docs) for the actual TTS path on `100.99.139.20:18141` — or for a separate TTS endpoint URL.
2. If none exists in the tailnet, evaluate **Azure Speech 神经语音** (Yunyang or Yunxi for a male companion voice; Xiaoxiao for female) — best Chinese TTS quality, sub-second latency from China-east region.
3. Once configured, set `LG_REMOTE_TTS_BASE_URL` env var; `RemoteTTS` activates automatically.

**Revisit date:** 2026-05-16 (after asking the endpoint owner about TTS availability).

## Plan impact
- **P3-T?** (TTSService, plan line ~3469, ~3559–3652): keep the protocol + both impls as planned. Default `selection = .local`. Remote impl ships as a stub that returns "not configured" until env var is set. No deletion of code, just a flipped default and a documented circuit breaker.
- **App config:** add `LG_REMOTE_TTS_BASE_URL` and (optionally) `LG_REMOTE_TTS_API_KEY` to Info.plist / env. Empty by default.
- **Demo runbook:** add "Voices → enable enhanced zh-CN Yunyang/Tingting" pre-flight step and "no headphones — speakers test sentence at venue ambient noise level" verification.
- **Spec §9:** A5 closed as `mitigation accepted` — the question of "which TTS sounds best" is unanswered (no audition was possible) but the engineering question of "what do we ship" is answered.
