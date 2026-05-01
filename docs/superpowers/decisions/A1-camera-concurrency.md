# Decision: Insta360 preview-stream + onboard recording concurrency

**ID:** A1 (matches spec §9)
**Date:** 2026-05-02
**Status:** open (provisional mitigation; revisit after hardware spike no later than 2026-05-09)
**Owner:** unassigned (needs the engineer who will hold the test camera + iPhone)

## Question
Can the Insta360 camera (model in hand) sustain a WiFi P2P preview stream **while simultaneously** recording video to its onboard storage, for at least 30 continuous minutes, without one channel dropping the other?

## Investigation
- Environment for this spike session: Windows MinGW64 host with no Xcode, no iPhone, no Insta360 hardware attached. **No empirical test was possible from this workstation.**
- Insta360 official developer portal (`https://www.insta360.com/sdk`) was not crawled in this session — it requires a developer account approval that is out of scope for a markdown-only spike.
- Insta360 support contact has **not** been messaged yet. Suggested message text (Chinese, ready to copy-paste) preserved below for whoever owns the hardware:

  > 对于 [具体型号]，能否同时进行（a）通过 WiFi 预览流向手机推送实时帧 和（b）相机本机录制完整视频？目标场景是 30 分钟散步全程并发。如不支持，是否有替代方案（如降帧率预览 / 周期性截图）能在录制期间获得相机视角？

- Public anecdotal evidence (Insta360 community forum, X3 / X4 threads) suggests preview + record concurrency works for short clips but preview frame-rate is throttled while recording, and some firmware versions drop the WiFi preview after ~10 min. **Not authoritative** — must be re-verified on the actual hand-held model + firmware.
- Spike scaffold directory `spike/A1_camera_concurrency/` is intentionally **not** created in this session (constraint: "Do NOT touch any code or files outside docs/superpowers/decisions/"). The owner of the hardware test must create it when they run the empirical test described in the plan (P0-T1 Step 3).

## Result
Unknown. The only honest result is "we have not yet tested this and we have not yet asked the vendor."

What is known:
- The plan's CameraBridge design assumes both channels work concurrently. If they do not, the design must change to **periodic snapshots while recording** or **time-sliced preview**.
- The walk loop generates a passive question approximately once per minute; therefore even a 0.2 fps "snapshot poll" preview would be sufficient functionally — but degrades the in-app live monitor experience.

## Decision (provisional, pending hardware spike)
**Provisional design assumption:** treat A1 as `mitigation accepted` for planning purposes, and design `CameraBridge` so that the consumer of preview frames is **agnostic to frame source** — it can be either:

1. a high-rate live preview stream (preferred, if vendor supports), **or**
2. a low-rate snapshot poll (1 frame every 2–5 s) pulled while recording is in progress (fallback).

Concretely: `CameraBridge.previewFrames: AsyncStream<CVPixelBuffer>` is the sole interface; the implementation behind it switches based on a runtime probe at session start. The app's UI live-view should already show "best-effort preview — may drop while recording" copy from day one so we are not promising what we cannot deliver.

**Action required before P1-T5 lands:** owner of the hardware must execute P0-T1 Step 3 (the empirical 5-minute walk test), record results in `spike/A1_camera_concurrency/notes.md`, and update this file's `Status` to `confirmed` or `architecture change required`.

**Revisit date:** 2026-05-09 (one week from today). If still open after that, escalate — this is a blocking item.

## Plan impact
- **P1-T5 (CameraBridge skeleton):** must be authored against the agnostic frame-stream interface. Implementation may swap between live preview and snapshot poll. Note already marked in plan with `// Per A1 spike outcome` comment at line ~927.
- **P3 walk loop:** must tolerate gaps in preview frames (use last-known frame for VLM calls). No change if A1 confirms; tightening required if `architecture change required`.
- **P4 keepsake:** unaffected — keepsake uses the on-camera recorded file, not the preview stream.
- **Demo runbook:** must list "verify preview survives recording for full 30-minute walk" as a pre-flight check.
