# LocalGravityTests / Fixtures

This directory holds binary test fixtures that are **not** committed to git
(they are large and may have ambiguous licensing). The test suite skips
gracefully (`XCTSkip`) when a fixture is absent, so a fresh clone still
builds + passes the non-fixture tests.

## fixture_360_30s.mp4

A ≥ 30-second h.264 MP4 used by:

- `ClipExtractorTests`
- `CaptionOverlayTests`
- `BGMMixerTests`
- `VideoAssemblerTests`

### How to drop one in

Any of these will work:

1. **Sample 360° clip from the camera** — record a 30 s clip on the
   Insta360 you actually intend to use, copy it via the companion app,
   and save it here as `fixture_360_30s.mp4`. This is the most realistic
   fixture and is preferred for VideoAssembler tests.

2. **Generic 360 sample** — Insta360, RICOH and GoPro all publish sample
   360 footage on their developer pages. Trim any sample to ≥ 30 s with
   ffmpeg:

   ```bash
   ffmpeg -i sample.mp4 -t 30 -c copy fixture_360_30s.mp4
   ```

3. **Synthetic placeholder** — for purely structural tests, a 30 s solid
   color h.264 file is sufficient:

   ```bash
   ffmpeg -f lavfi -i color=c=teal:s=1920x1080:d=30 -c:v libx264 \
       -pix_fmt yuv420p fixture_360_30s.mp4
   ```

### Why this is gitignored

- File size (typically 10–50 MB).
- Licensing — vendor sample footage is usually evaluation-only; we do not
  want it in the public history.
- Reproducibility — we want anyone to be able to regenerate it locally.

If you need a deterministic CI fixture, use option 3 (the synthetic
ffmpeg one) and check it in as a release artifact, not in git.
