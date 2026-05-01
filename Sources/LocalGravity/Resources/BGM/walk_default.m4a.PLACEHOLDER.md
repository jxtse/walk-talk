# `walk_default.m4a` — required BGM track

This file is intentionally **not committed**. The keepsake video pipeline
(`BGMMixer`) loads `walk_default.m4a` from this directory at runtime; ship
the binary by dropping it in here before building the app.

## Why no binary in git?

We have not yet selected a license-cleared track and committed the wrong
file would publish it under whatever the repo license is. The placeholder
keeps the path documented without smuggling in unverified audio.

## Where to source one (royalty-free, attribution-friendly)

Pick **one** of these and download the AAC/M4A version (or convert with
`ffmpeg -i in.mp3 -c:a aac -b:a 192k walk_default.m4a`):

1. **YouTube Audio Library** — e.g. *"Acoustic Breeze"* (Bensound-style,
   CC-BY equivalent). Filter by "No attribution required" if you want to
   skip the credit.
   <https://www.youtube.com/audiolibrary>

2. **Pixabay Music** — Pixabay license, free for commercial use, no
   attribution required. Search "walking", "ambient", "lofi acoustic":
   <https://pixabay.com/music/>

3. **FreePD** — public-domain dedications by Kevin MacLeod et al.:
   <https://freepd.com/>

4. **Bensound** — free with attribution, paid licenses available:
   <https://www.bensound.com/royalty-free-music>

## Drop-in steps

```bash
# from the repo root
cp ~/Downloads/your_chosen_track.m4a \
   Sources/LocalGravity/Resources/BGM/walk_default.m4a
```

Then rebuild. The SPM `Package.swift` should declare the `BGM/` folder as
a resource (`.process` or `.copy`). Verify with:

```bash
swift test --filter BGMMixerTests
```

If the tests still skip with `bgmNotFound`, double-check the file
extension (`.m4a`, not `.mp3`) and that the resource bundle includes the
`BGM/` subdirectory.

## Constraints for whatever you pick

- Loopable or at least monotone ending — `BGMMixer` loops the file
  end-to-end to fill the video duration.
- Length: 30–120 s is fine.
- Bitrate: 128–192 kbps AAC.
- Loudness: aim for −18 LUFS so it sits under spoken captions; the
  spec (§5.2) calls for low-volume duck during caption windows (P6
  polish if needed).
- License: explicitly compatible with commercial app distribution.

## Tracking

When you commit the actual binary later, also update:
- This file → list the chosen source + license.
- `docs/superpowers/plans/checkpoints/P5-closeout.md` → cite the source.
- The commit message → `chore(p5): add walk_default BGM (Pixabay - <name>)`.
