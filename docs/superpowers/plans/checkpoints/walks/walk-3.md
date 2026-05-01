# Walk #3 — Full dress rehearsal

**Task:** P6-T4
**Goal:** Walk the **exact route + script** that will be used for the demo, time-boxed to the actual demo length, producing the keepsake that will be played in the demo. This walk's numbers feed `demo-script.md` claims and ship-readiness gating.
**Owner:** <fill in>
**Date / start time:** YYYY-MM-DD HH:MM
**Demo slot length:** __ min (default 30; shorten if competition slot < 30)

> Walk-1 + Walk-2 must both be PASS, with all blockers resolved, before walk-3.

---

## 1. Pre-flight checklist

Same as `walk-1.md` §1, plus:

- [ ] App build version: `__________` is **frozen** — no further code changes after walk-3 unless ship-blocker found.
- [ ] Route is the **same** as walk-1 (or the explicitly-chosen demo route — record it here): _____________
- [ ] Demo script draft (`docs/superpowers/demo/demo-script.md`) is open on副机 — speaking lines will be rehearsed during the walk.
- [ ] Stopwatch ready — every beat below must be timed.
- [ ] **Recording**: a companion films you (third-person) for backup B-roll. Phone screen recording also on (in case live demo needs replay).
- [ ] Keepsake destination folder ready to copy artifact out of the device after the walk.

---

## 2. Stopwatch — these numbers feed the demo script

Fill in **every** field. Demo script will quote these.

| Beat | Target | Actual (mm:ss) | Notes |
|---|---|---|---|
| Walk start (App enters `walking`) | 00:00 | | |
| First proactive utterance | ≤ 5:00 | | content: ___ |
| First passive Q&A — end-to-end latency | ≤ 3.0 s | | actual ___ s |
| First record_moment — confirmation latency | ≤ 1.5 s | | actual ___ s |
| Last proactive utterance | by 28:00 | | total proactive count: __ (≤ demo-length × 0.3) |
| "散步结束" said | demo-length − 1:00 | | |
| State → `ending` | within 2 s of "散步结束" | | |
| Keepsake produced | ≤ 90 s wall-clock | | actual ___ s |
| Keepsake duration | 30–60 s | | actual ___ s |
| Keepsake kind | video preferred | | video / poster |

**Hard fail (block ship):**
- App crash, hang > 10 s, keepsake not produced, or proactive count > (demo-length / 10) × 3 over the run.

---

## 3. Final perceived-quality scoring

Use the rubric from `walk-1.md` §5.

| Dimension | Score 1–5 | Notes |
|---|---|---|
| Keepsake overall | __ | |
| 360° clip recognizability | __ | Would a stranger see "this is 360"? |
| Map-track legibility | __ | |
| Caption / narration relevance | __ | |
| Poster-fallback (if applicable) | __ | |

**Ship gate (per spec §11 + plan P6-T4 step 3):**
**Keepsake overall ≥ 3 → may ship. < 3 → block, file fix tasks, re-walk.**

Final result: **____ / 5**

---

## 4. Observations

```markdown
# Walk 3 — YYYY-MM-DD HH:MM — dress rehearsal
- Demo length: __ min
- Duration (actual): __ min
- Proactive total: __  (cap: __)
- Passive Q&A: __ asked / __ answered well / __ "我没看清"
- record_moment: __
- Latency complaints: <list — these MUST be addressed if any>
- Crashes / hangs: <list — any => re-walk>
- Keepsake quality (overall): __ / 5
- 360° recognizability: __ / 5
- Subjective verdict for demo: GO / NO-GO
- Bugs filed: <ids>
```

---

## 5. Artifacts saved (for demo)

The following files must be copied off-device and stored in `docs/superpowers/demo/assets/` (or referenced if too large):

- [ ] Final keepsake video / poster — filename: ____
- [ ] Backup poster (in case video corrupts at venue) — filename: ____
- [ ] Walk-3 raw 360° footage (at least one good 5–10 s clip) — filename: ____
- [ ] Screen recording of the App during walk-3 (for video-fallback demo) — filename: ____
- [ ] Companion's third-person video (for handout / deck) — filename: ____

---

## 6. Post-walk actions

- [ ] Numbers from §2 transcribed into `demo-script.md` (replace any `<walk-3 actual>` placeholders).
- [ ] Quality score from §3 transcribed into `SHIP.md` evidence row.
- [ ] Commit:

```bash
git add docs/superpowers/plans/checkpoints/walks/walk-3.md
git commit -m "docs(p6): walk 3 dress rehearsal"
```

---

## 7. Sign-off

- [ ] Walked: _______________  Date: _______________
- [ ] Quality ≥ 3/5: yes / no
- [ ] Demo GO: yes / no  (if no — list what blocks)
