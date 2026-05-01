# P4 close-out

**Phase:** P4 — Keepsake v1 / Poster fallback
**Status:** ⬜ pending real-walk acceptance (fill in on Mac)
**Date:** YYYY-MM-DD
**Real walks:** <n>

---

## Acceptance protocol

Take **one walk per condition** below. After each walk, attach the
generated poster (PNG) into `docs/superpowers/plans/checkpoints/walks/`
and link it from the row.

| # | Condition | How to force | Expected | Result | Artifact |
|---|---|---|---|---|---|
| 1 | **Best path** — good network, all APIs reachable | nothing | poster has AI image + map + stats + 1–5 highlights | ⬜ pass / ⬜ fail | `walks/p4-best.png` |
| 2 | **Diffusion failed** | block `100.99.139.20:18141` *or* set `DiffusionClient(model: "nope")` | poster still produced; AI-image slot replaced by clean white space; map + stats still present | ⬜ pass / ⬜ fail | `walks/p4-no-diffusion.png` |
| 3 | **Script failed (failsafe)** | block the LLM endpoint entirely (e.g. airplane mode after walk start, before pressing 结束散步) | failsafe poster: title `一段散步`, narration `脚步会记得这条路。`, map (if track captured), stats | ⬜ pass / ⬜ fail | `walks/p4-failsafe.png` |

> The **failsafe invariant** is the gate. If condition 3 fails, P4 is not closed.

---

## Code-level acceptance (already green from this worktree)

- [x] `MaterialCollector` returns `KeepsakeMaterials` with correct distance / duration
- [x] `MapRenderer.center` / `zoomLevel` / `renderStaticSnapshot` produce stable output
- [x] `ScriptGenerator` parses a well-formed JSON response, throws `.parse` on garbage
- [x] `DiffusionClient` decodes a base64 PNG and surfaces HTTP errors as `.http`
- [x] `PosterComposer` produces a non-empty 1024-wide image even with no AI poster + no map
- [x] `KeepsakeBuilder.buildPoster` returns a non-trivial PNG when both LLM and diffusion fail

Re-run on Mac with `swift test` (or `xcodebuild test`) to confirm before
recording the real-walk results.

---

## Open issues for P5

- [ ] **Reconcile with P5 sketch.** A parallel-written P5 worktree
      (commit `7e9cf19`) shipped a `KeepsakeBuilder` + `WalkScreen+ShareV2`
      + `KeepsakeBuilderV2Tests` that assume a different protocol surface
      (`KeepsakeScripting` / `DiffusionGenerating` / `PosterComposing` /
      `VideoAssembling`, `KeepsakeResult`, `KeepsakeScript(videoClips:posterText:)`,
      `KeepsakeMaterials.videoFile`). P4's canonical surface ships
      `ScriptGenerator` / `DiffusionClient` / `PosterComposer` /
      `KeepsakeOutput`, `KeepsakeScript(title:narration:posterPrompt:videoClips:bgmTag:highlightMomentIds:)`,
      and `KeepsakeMaterials.videoURL`. P5 needs to either:
        (a) wrap the canonical builder by adding `VideoAssembling` as an
            optional dep on top of `KeepsakeBuilder.buildPoster`, OR
        (b) bridge its `*ing` protocols onto the concrete P4 types.
      Tracked here so P5 close-out doesn't lose this thread.
- [ ] (other items as discovered during real walks)

## Risks / known degradation behaviours observed during walks

- (fill in)
