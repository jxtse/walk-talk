<!-- docs/superpowers/plans/checkpoints/walks/P3-walk-2.md -->
# P3 Walk 2 — YYYY-MM-DD

> **Template — fill in on Mac after the second 玄武湖 walk.** This file is
> the acceptance artifact for P3-T8. It uses the same template as Walk 1
> with an added "diff vs Walk 1" section because this walk's purpose is to
> validate that the adjustments made between walks (`fix(p3): …` /
> `feat(p3): …` commits) actually moved the needle.

**Engineer:**
**Route:** 玄武湖 east side (start / end coordinates)
**Duration (minutes):**
**Battery drained:** phone __% , camera __%
**Weather / time of day:**
**Network path used:** Tailscale on phone hotspot / public reverse proxy / backup model

---

## Adjustments since Walk 1

<!-- one bullet per commit between Walk 1 and Walk 2 -->
- _commit hash + one-line summary_

## Pre-flight checklist

- [ ] All Walk 1 pre-flight items still hold
- [ ] Walk 1 known-bug list re-checked

---

## Walk script (same as P3-T7)

1. **Passive Q&A.** "嘿，那是什么花？"
2. **Proactive recommendation.** Walk near a 茶馆, wait ~30s.
3. **Passive capture.** "记一下我刚才说的那个想法"
4. **Direction guide.** "带我去湖那边"
5. **Silence respected.** 5 minutes silent.

## Scenario outcomes

| # | Scenario | Pass / Fail | Latency observed | Notes |
|---|----------|-------------|------------------|-------|
| 1 | Passive Q&A |  |  |  |
| 2 | Proactive recommendation |  |  |  |
| 3 | Passive capture |  |  |  |
| 4 | Direction guide |  |  |  |
| 5 | Silence respected |  |  |  |

## Diff vs Walk 1

| Metric | Walk 1 | Walk 2 |
|---|---|---|
| Scenarios passed (of 5) |  |  |
| Proactive utterances |  |  |
| TTS local-fallback count |  |  |
| Avg agent turn latency (p50) |  |  |
| Crashes |  |  |

## Acceptance criteria (gate to advance to P4)

- [ ] All 5 scenarios pass on this walk **OR** Walk 1 already had all 5 passing.
- [ ] Proactive utterances ≤ 3 over the 30-min walk.
- [ ] Camera video file downloaded successfully.
- [ ] No new crashes introduced by Walk 1 → Walk 2 adjustments.
- [ ] No regressions versus Walk 1 in the diff table above.

## Bugs / surprises

-

## Decisions

-

## Raw artifacts

- Camera video file: `<path on phone>`
- Moment log dump: `<paste JSON>`
- GPS track length (points): _
- Total agent turns: _
