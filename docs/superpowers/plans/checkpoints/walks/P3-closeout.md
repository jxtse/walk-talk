<!-- docs/superpowers/plans/checkpoints/walks/P3-closeout.md -->
# P3 close-out

> **Template — fill in on Mac after the gate is met.** This file is the
> formal P3 → P4 handoff per P3-T9. The gate is: **at least one walk under
> `walks/` had all 5 scenarios passing AND ≤3 proactive utterances.**
> Tag `p3-done` after committing.

**Date:** YYYY-MM-DD
**Engineer:**
**Walks completed:** _ (links: `walks/P3-walk-1.md`, `walks/P3-walk-2.md`, …)
**First fully-passing walk:** Walk _

---

## Gate verification

- [ ] One walk has all 5 scenarios passing (link: _)
- [ ] That walk had ProactiveQuota holding (≤ 3 proactive utterances)
- [ ] That walk produced a usable raw video file
- [ ] That walk produced a non-empty `MomentLog`
- [ ] No outstanding crash bugs

## Stable behaviors (carry forward to P4/P5 unchanged)

-

## Known soft issues (deferred to P6 polish)

-

## Decisions affecting P4/P5

<!-- e.g.: "video file size at 30min ~X MB; KeepsakeBuilder must trim before upload"
         "AudioIO never had to fall back to local TTS more than once per walk; safe to assume remote TTS is the steady state" -->

-

## Tagging

```bash
git tag p3-done
```
