# P5 close-out

**Date:** 2026-05-02 (template — fill in real-walk numbers on Mac)
**Tag (after acceptance):** `p5-done`

## Status: code complete, runtime verification deferred

P5 was implemented on Windows / MinGW64 with no Xcode or AVFoundation
runtime available. All code is committed; the four real-walk acceptance
runs below MUST be executed on Mac before tagging `p5-done`.

## Tasks shipped

| Task | File(s) | Commit |
|------|---------|--------|
| P5-T1 | `Sources/LocalGravity/Keepsake/Video/TrackAnimRenderer.swift`, `MapRenderer+Partial.swift`, `UIImage+PixelBuffer.swift` | `feat(p5): track-anim intro renderer (mp4 via AVAssetWriter)` |
| P5-T2 | `Sources/LocalGravity/Keepsake/Video/ClipExtractor.swift`, `Tests/.../Fixtures/README.md` | `feat(p5): clip extractor via AVAssetExportSession` |
| P5-T3 | `Sources/LocalGravity/Keepsake/Video/CaptionOverlay.swift` | `feat(p5): caption overlay via CALayer + CAKeyframeAnimation` |
| P5-T4 | `Sources/LocalGravity/Keepsake/Video/BGMMixer.swift`, `Resources/BGM/walk_default.m4a.PLACEHOLDER.md` | `feat(p5): bgm mixer + default royalty-free track placeholder` |
| P5-T5 | `Sources/LocalGravity/Keepsake/Video/VideoAssembler.swift` | `feat(p5): video assembler — intro + clips + outro + bgm` |
| P5-T6 | `Sources/LocalGravity/Keepsake/KeepsakeBuilder.swift`, `Sources/LocalGravity/UI/WalkScreen+ShareV2.swift` | `feat(p5): KeepsakeBuilder v2 — video-first with hard poster fallback` |

## Outstanding before Mac verification

1. **Drop in `walk_default.m4a`** per
   `Sources/LocalGravity/Resources/BGM/walk_default.m4a.PLACEHOLDER.md`.
   Recommendation (cite in commit message): Pixabay → "Acoustic
   Breeze"-style track or YouTube Audio Library track flagged "No
   attribution required". Track file MUST sit at
   `Sources/LocalGravity/Resources/BGM/walk_default.m4a`.

2. **Drop in `fixture_360_30s.mp4`** per
   `Tests/LocalGravityTests/Fixtures/README.md`.

3. **Wire `WalkScreen` ShareLink to call `WalkScreen.keepsakeShareLink(for:)`**
   added in `Sources/LocalGravity/UI/WalkScreen+ShareV2.swift`. Replace
   any P4 `ShareLink(item: posterURL)` site with that helper.

4. **Confirm `MapRenderer`, `KeepsakeMaterials`, `KeepsakeScript`,
   `KeepsakeError`, `PosterComposer`, `PosterComposing`,
   `KeepsakeScripting`, `DiffusionGenerating`, `LGLog`, `GPSPoint`,
   `TestFixtures`** types exist (introduced by P1–P4). The P5 code
   refers to them as if they exist; if any signatures drifted during
   P4, reconcile here before running tests.

## Acceptance results (fill on Mac)

Take one walk (or replay one captured session); produce four runs
against the same materials by toggling deps:

| # | Path | Expected | Result | Duration | File size | Notes |
|---|------|----------|--------|----------|-----------|-------|
| 1 | Best path: video MP4 with intro + 3 clips + captions + BGM + outro freeze | `kind == .video`, 30–60 s, ≤ 50 MB | _pending_ | _s_ | _MB_ | |
| 2 | No video file: delete cached recording | `kind == .poster` | _pending_ | n/a | n/a | KeepsakeBuilder skips V2 path |
| 3 | Assembler crash: inject `StubVideoAssembler(.failure)` | `kind == .poster` | _pending_ | n/a | n/a | warn-logged, no throw |
| 4 | No script: force LLM endpoint failure | `kind == .poster`, failsafe text rendered | _pending_ | n/a | n/a | failsafe script has 0 clips → V2 skipped |

## Hard fallback invariant — verified by

- `KeepsakeBuilderV2Tests.test_build_fallsBackToPoster_whenVideoFails`
- `KeepsakeBuilderV2Tests.test_build_fallsBackToPoster_whenNoVideoFile`
- `KeepsakeBuilderV2Tests.test_build_fallsBackToPoster_whenScriptHasNoClips`
- `KeepsakeBuilderV2Tests.test_build_failsafeScript_whenScripterThrows_andStillReturnsPoster`
- `KeepsakeBuilderV2Tests.test_build_propagatesPosterFailure` (P4 floor preserved)
- `KeepsakeBuilderV2Tests.test_build_posterOnlyMode_whenVideoNil`

These run on any platform with Foundation — they do NOT need
AVFoundation or the binary fixtures.

## Known issues for P6

- BGM ducking under captions (spec §5.2) is **not** implemented; current
  `BGMMixer` is constant-volume. P6 polish task if time permits.
- `VideoAssembler` runs export at `AVAssetExportPresetHighestQuality` —
  may produce > 50 MB on long walks. Re-evaluate against real
  walk-1/walk-2 outputs and switch to `AVAssetExportPreset1280x720` if
  size is a concern.
- `MapRenderer.snapshotPartial` uses a local bbox helper; if P4 already
  exposes one, deduplicate.
- Caption font/positioning are conservative defaults — tune from real
  walk-1 footage if legibility is poor.
- The Insta360 recording is assumed to be h.264 readable by
  AVAssetExportSession. If the camera writes HEVC, transcoding may be
  needed (P6).
- `WalkScreen` integration is opt-in (extension method). Confirm the UI
  batch wires it before demo.

## Sign-off

- [ ] All four acceptance rows above marked PASS.
- [ ] `swift test` (or `xcodebuild test -scheme LocalGravity`) green
      on Mac, including P5 tests.
- [ ] BGM track committed (with attribution recorded in placeholder doc).
- [ ] Poster fallback invariant verified end-to-end on a real walk.
- [ ] `git tag p5-done` pushed.
