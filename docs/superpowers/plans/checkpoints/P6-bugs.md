# P6 Bug Tracker

Bugs discovered during P6 real-walk checkpoints (walk-1, walk-2, walk-3).
Populated by the user after each walk; resolved by P6-T2 (blockers) before the next walk.

---

## Schema

Each entry below uses this exact YAML-ish block:

```
- id:        BUG-P6-NNN              # zero-padded, e.g. BUG-P6-001
  title:     <one-line summary>
  walk:      walk-1 | walk-2 | walk-3
  found_at:  YYYY-MM-DD HH:MM (local)
  severity:  blocker | major | polish
  area:      camera | gps | audio | agent | tools | keepsake | ui | network | other
  repro:     |
    1. <step>
    2. <step>
    3. <observed>  vs  <expected>
  evidence:  <log path / screenshot path / timestamp in walk recording>
  fix-task:  <task id, e.g. P6-T2-fix-001 — filled when fix dispatched>
  status:    open | in-progress | resolved | wont-fix (with reason)
  resolved-commit: <sha — filled when status becomes resolved>
```

**Severity guide:**
- **blocker** — App crashes, data loss, AI breaks contract (e.g. exceeds proactive quota), keepsake fails to produce **anything**, or any item that would make the demo fail. Must be fixed before next walk (P6-T2 gates on this).
- **major** — Functional but degraded UX (e.g. STT mishears 30% of the time, latency 4s+, keepsake quality 2/5). Fix before walk-3 if possible; otherwise log to known-issues.
- **polish** — Cosmetic, edge-case, nice-to-have. Defer post-demo.

---

## Open

<!-- Add new entries here. Move to "Resolved" once status becomes resolved. -->

(none yet — populate after walk-1)

---

## Resolved

<!-- Move resolved entries here for an audit trail. -->

(none yet)

---

## Won't-fix / Deferred

<!-- Things explicitly out of scope, with reason. -->

(none yet)
