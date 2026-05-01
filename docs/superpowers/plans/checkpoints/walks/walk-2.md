# Walk #2 — Adversarial path (degradation drill)

**Task:** P6-T3
**Goal:** Inject one fault per leg of the walk and verify the documented degradation paths from spec §6 actually fire. **Must hold** before walk-3.
**Owner:** <fill in>
**Date / start time:** YYYY-MM-DD HH:MM
**Weather:** <>
**Route:** <same as walk-1 if possible — keep variables down>

> Walk-1 must be done and all its blockers resolved (P6-T2) before starting this walk. If they are not, **abort and finish P6-T2**.

---

## 1. Pre-flight checklist

Same as `walk-1.md` §1 — copy and re-tick. **Do not skip.**

Additional walk-2-specific items:
- [ ] Companion (or副机 timer) is briefed on the **fault-injection schedule** below — they must hit the toggles on cue.
- [ ] Tailscale / VPN switch is reachable mid-walk (test toggle once before starting).
- [ ] Camera Wi-Fi toggle path verified (settings → Wi-Fi → forget Insta360 SSID).
- [ ] App build version: `__________` (must include all walk-1 fixes).
- [ ] `walk-2.md` open on副机 with stopwatch.

---

## 2. Fault-injection schedule (the drill)

> **Walk for 30 minutes total. Do not deviate from the schedule.** If a leg fails outright (app crash) record it and proceed — do not "redo" the leg.

### Leg A — minutes 0:00 – 10:00 — Camera Wi-Fi disconnect

- 0:00 — start walk normally; AI / GPS / dialog all up.
- ≈ 3:00 — companion (or you) **turns off camera Wi-Fi** (forget SSID or power-cycle camera).
- 3:00 – 10:00 — keep walking, ask passive Q&A (~ 2 questions), trigger record_moment once, accept one recommendation if AI offers one.

**Expected per spec §6:**
- App shows reconnect hint (non-blocking).
- GPS + STT/TTS + agent dialog **continue uninterrupted**.
- VLM-dependent answers fall back to "我没看清" (or equivalent) — not crash.
- record_moment still records (uses current GPS + dialog context, video gap acceptable).

### Leg B — minutes 10:00 – 20:00 — LLM endpoint unreachable

- 10:00 — companion **turns off Tailscale / VPN** (or kill LLM endpoint route).
- 10:00 – 20:00 — re-connect camera (Leg A fault now removed); ask 2 passive Q&A; do **not** speak for 5 continuous minutes mid-leg to test silence behaviour (no proactive should fire — there is no LLM).

**Expected per spec §6:**
- Proactive推荐 silenced cleanly — no errors surfaced to user.
- Passive Q&A returns the configured fallback line ("我现在听不太清，等会再聊？" or whatever P3-T3 set).
- No crash, no infinite retry-spinner.
- Quota counter does not advance (no proactive utterances issued).

### Leg C — minutes 20:00 – 30:00 — Recovery + finish

- 20:00 — companion **re-enables VPN**; verify `/v1/models` reachable from device (副机 ping or in-app status indicator).
- 20:00 – 29:00 — normal walk; aim for at least 1 recommendation accepted, 1 record_moment.
- 29:00 — say "散步结束".
- Wait for keepsake.

**Expected:**
- Keepsake **must be produced** — at minimum poster fallback (per spec §6 "视频合成失败 → 降级长图，必须保证至少有一种纪念品产出").
- 360° clip may be partial / missing (Leg A had no camera). Acceptable.

---

## 3. Stopwatch beats (fill in)

| Event | Time (mm:ss) | Pass / Fail | Notes |
|---|---|---|---|
| Walk start | 00:00 | — | |
| Camera Wi-Fi off (Leg A inject) | | | |
| First passive Q&A under no-camera | | | Fallback used? Y / N |
| record_moment under no-camera | | | Captured? Y / N |
| VPN off (Leg B inject) | | | |
| First passive Q&A under no-LLM | | | Fallback line text: ___ |
| 5-min silence — proactive count during silence | | | Should be 0 |
| VPN restored (Leg C) | | | LLM ping OK? Y / N |
| First successful proactive after recovery | | | |
| "散步结束" | | | |
| Keepsake produced | | | kind: video / poster |

---

## 4. Per-leg result rubric

For each leg below, mark **PASS** only if the spec §6 expectations were met and no app crash occurred.

### Leg A — Camera dropout

- [ ] PASS — degradation matched spec §6 row 1
- [ ] FAIL — describe: ____

### Leg B — LLM unreachable

- [ ] PASS — degradation matched spec §6 row 2
- [ ] FAIL — describe: ____

### Leg C — Recovery + keepsake

- [ ] PASS — keepsake produced (video or poster), app stable
- [ ] FAIL — describe: ____

**Walk-2 overall PASS requires all three legs PASS.** Any FAIL → file as blocker, fix, **re-walk leg or full walk-2 before walk-3**.

---

## 5. Observations (fill in)

```markdown
# Walk 2 — YYYY-MM-DD HH:MM — adversarial
- Duration (actual): __ min
- Leg A result: PASS / FAIL — <notes>
- Leg B result: PASS / FAIL — <notes>
- Leg C result: PASS / FAIL — <notes>
- Total proactive utterances: __ (target ≤ 9)
- Crashes: <list>
- Unexpected behaviour (non-spec): <list>
- Keepsake: kind ___, duration ___ s, quality 1–5: __
- Bugs filed: <ids>
- Subjective verdict: "demo-ready under faults?" yes / no — <one sentence>
```

---

## 6. Post-walk actions

- [ ] File any new bugs into `../P6-bugs.md`. Anything that broke the documented degradation contract = **blocker**.
- [ ] If blockers: fix, then **re-run the failing leg** (or full walk-2 if multiple legs broken). Update this file with new run timestamps.
- [ ] Save raw artifacts to `~/walk-talk-walks/walk-2/` (gitignored).
- [ ] Commit:

```bash
git add docs/superpowers/plans/checkpoints/walks/walk-2.md docs/superpowers/plans/checkpoints/P6-bugs.md
git commit -m "docs(p6): walk 2 (adversarial) + fixes"
```

---

## 7. Sign-off

- [ ] Walked: _______________  Date: _______________
- [ ] All three legs PASS: yes / no
- [ ] Ready for P6-T4 (dress rehearsal): yes / no
