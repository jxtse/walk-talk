<!-- docs/superpowers/plans/checkpoints/walks/P3-walk-1.md -->
# P3 Walk 1 — YYYY-MM-DD

> **Template — fill in on Mac after the real 玄武湖 walk.** This file is
> the acceptance artifact for P3-T7. Do not advance to P4 until at least
> one walk has all 5 scenarios passing (per P3-T9 close-out gate).

**Engineer:**
**Route:** 玄武湖 east side (start / end coordinates)
**Duration (minutes):**
**Battery drained:** phone __% , camera __%
**Weather / time of day:**
**Network path used:** Tailscale on phone hotspot / public reverse proxy / backup model

---

## Pre-flight checklist

- [ ] iPhone fully charged
- [ ] Insta360 camera fully charged, paired over WiFi
- [ ] Bluetooth earphones paired
- [ ] Tailscale (or A3-chosen path) active and ping-tested
- [ ] LLM endpoint `/v1/models` returns 200 from phone
- [ ] All §9 LOOKUPs in `Insta360CameraBridge` resolved (or known-degraded
      with documented fallback in `docs/superpowers/decisions/A1`/`A2`)
- [ ] `Secrets.plist` populated on the test device
- [ ] App built in Release configuration on the test phone

---

## Walk script (perform each at least once, in any order)

1. **Passive Q&A.** Speak: "嘿，那是什么花？" — expect VLM answer in earphone within ~5s.
2. **Proactive recommendation.** Walk near a known POI (e.g., a 茶馆) and stay still for ~30s — expect proactive recommendation.
3. **Passive capture.** Speak: "记一下我刚才说的那个想法" — expect silent record (no TTS reply); a `Moment` should land in `MomentLog` with a valid GPS.
4. **Direction guide.** Speak: "带我去湖那边" — expect bearing + distance in earphone.
5. **Silence respected.** Stay silent for 5 minutes — verify the AI does NOT speak unprompted (proactive_quota holds).

---

## Scenario outcomes

| # | Scenario | Pass / Fail | Latency observed | Notes |
|---|----------|-------------|------------------|-------|
| 1 | Passive Q&A |  |  |  |
| 2 | Proactive recommendation |  |  |  |
| 3 | Passive capture |  |  |  |
| 4 | Direction guide |  |  |  |
| 5 | Silence respected |  |  |  |

## Acceptance criteria (all must be true to count Walk 1 as passing)

- [ ] All 5 scenarios above marked **pass**.
- [ ] Proactive utterances over the 30-min walk: **≤ 3** (ProactiveQuota held).
- [ ] Camera video file downloaded to phone successfully (file exists, non-zero size, opens in Photos / Files).
- [ ] Track buffer captured ≥ 1 GPS point per ~10 seconds for the duration.
- [ ] No crashes; no `WalkSession` transitions to `.failed`.
- [ ] TTS fallback to local `AVSpeechSynthesizer` triggered ≤ 1 time over the walk
      (if higher, log timings and revisit the 1.5s threshold).

---

## Bugs / surprises

-

## Decisions

<!-- bullet list of small adjustments made: prompt tweaks, threshold changes, etc. Each adjustment should be its own commit per P3-T8 step 1. -->

-

## Raw artifacts

- Camera video file: `<path on phone>`
- Moment log dump: `<paste JSON>`
- GPS track length (points): _
- Total agent turns: _
- Tool-call breakdown: speak_to_user= , record_moment= , get_camera_frame= , analyze_frame_vlm= , amap_*= 
