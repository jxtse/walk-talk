# Decision: Keepsake background music source

**ID:** A6 (matches spec §9)
**Date:** 2026-05-02
**Status:** confirmed (curated royalty-free pack from Pixabay Music + Free Music Archive; Apple Music ruled out)
**Owner:** unassigned (whoever curates the 5–8 tracks before P5-T1)

## Question
What background music plays under the keepsake video? Options:
- (a) curated royalty-free pack bundled in app
- (b) iOS system sounds / Apple Music API (licensing concerns)
- (c) user picks from their library at export time
- (d) no music — only ambient sound

## Investigation
- **Apple Music API (option b):** the `MusicKit` API only allows playback during the user's active subscription session and **forbids** muxing audio into an exported video file under Apple's Apple Music Web/SDK terms. Hard rejection — would block App Store review and may infringe label rights.
- **User picks from library (option c):** user-supplied library tracks may be DRM-protected (Apple Music) — `AVAssetExportSession` will refuse to embed them. Even non-DRM tracks raise a "do you have rights to share this?" UX question. Defer to a v2 feature once the bundled pack is shipped.
- **Ambient only (option d):** for outdoor walking video the ambient sound is wind + traffic + footstep crunch — usually unflattering and inconsistent across walks. Bad default; can remain a user toggle.
- **Curated royalty-free pack (option a):** the pragmatic MVP path. Three viable sources researched:

| Source | License | Suitability | URL |
|---|---|---|---|
| **Pixabay Music** | Pixabay Content License (free for commercial + non-commercial use, no attribution required, no royalties) | Excellent — large catalog of cinematic/calm/upbeat instrumental tracks; downloads as MP3, easy to convert to AAC/M4A for iOS | https://pixabay.com/music/ |
| **Free Music Archive (FMA)** | Per-track CC0 / CC-BY / CC-BY-SA / CC-BY-NC — must verify each track's license | Good — high-quality curated tracks, but each track requires individual license check; some tracks require attribution credit roll | https://freemusicarchive.org/ |
| **ccMixter** | CC-BY (most tracks) — requires attribution | Acceptable — strong electronic/ambient catalog but attribution requirement is a UX wart for short clips | https://ccmixter.org/ |
| Incompetech (Kevin MacLeod) | CC-BY 4.0 — requires attribution | Acceptable backup — well-known, predictable quality | https://incompetech.com/music/royalty-free/ |

## Result
- Apple Music / user-library paths are blocked by licensing/DRM for MVP.
- Pixabay Music is the cleanest legal path (no attribution, no royalties, commercial-OK) and can supply 5–8 mood-varied instrumental tracks in under an hour of curation.
- FMA is the secondary source for any niche mood Pixabay can't fill — but each track requires a per-license check and possibly an in-app attribution screen.

## Decision
**Bundle 5–8 royalty-free instrumental tracks under `WalkTalk/Resources/bgm/`**, sourced primarily from **Pixabay Music** (Pixabay Content License) and secondarily from **Free Music Archive** (CC0 or CC-BY tracks only — never CC-BY-NC, never CC-BY-SA).

**Mood matrix to fill (one track each):**
| Mood tag | Use case | Source preference |
|---|---|---|
| `calm` | Lake stroll, gentle weather | Pixabay |
| `contemplative` | Sunset, reflective walk | Pixabay |
| `upbeat` | Sunny, fast pace, with friend | Pixabay |
| `wistful` | Solo walk, autumn/winter | Pixabay or FMA CC0 |
| `playful` | Park, kids, dogs nearby | Pixabay |
| `cinematic` | Demo/showcase clip | Pixabay |
| `ambient_nature` | Use almost-no-music backdrop | Pixabay or FMA CC0 |

**LLM-driven selection:** the keepsake script generator (P5) emits a `mood` tag chosen from the list above; `BGMMixer` maps tag → file. If the LLM emits an unknown tag, fall back to `calm`.

**License compliance:**
- Pixabay tracks: no attribution required, but **store the source URL + download date in `WalkTalk/Resources/bgm/LICENSES.md`** (to be created in P5-T1) for our own audit trail.
- Any CC-BY tracks (if used as backup): must show a one-line attribution in the app's Settings → Credits screen. Avoid CC-BY in the keepsake video itself if possible to keep clip endings clean.

**Tracks are NOT downloaded in this P0 step.** Per plan, P5-T1 owns the actual `.m4a` files and the `LICENSES.md` ledger. This decision file commits us to the source + license model only.

**Apple Music API is permanently rejected** for MVP. User-library picking is deferred to a post-MVP v2 feature with explicit "you confirm you have rights" UI.

**Note on plan's `.gitkeep` step:** the plan asks to also create `WalkTalk/Resources/bgm/.gitkeep` here. This task's constraint is "do not touch files outside `docs/superpowers/decisions/`", so directory creation is **deferred** to whoever lands the Xcode project scaffold (P1) or P5-T1 (whichever is first to need the path). No information is lost.

## Plan impact
- **P5-T1 (BGM bundling):** download 5–8 Pixabay tracks per mood matrix above, normalize to ~-18 LUFS, convert to `.m4a`, place under `WalkTalk/Resources/bgm/<mood>.m4a`, write `LICENSES.md` next to them.
- **P5 keepsake script generator:** prompt the LLM to emit a `mood` field from the closed vocabulary above.
- **P5 BGMMixer:** map mood → filename, duck under captions per spec §6.
- **App settings screen:** add a "Credits" sub-page; populate only if any CC-BY tracks ship.
- **No App Store review risk** for the chosen path — Pixabay license is explicitly commercial-OK, no royalty.
