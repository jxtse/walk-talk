# Decision: Insta360 iOS SDK feature completeness

**ID:** A2 (matches spec §9)
**Date:** 2026-05-02
**Status:** open (provisional; revisit after SDK download + sample-app run no later than 2026-05-09)
**Owner:** unassigned (needs the engineer with macOS + Xcode + the test camera)

## Question
Does the Insta360 iOS SDK (latest version) expose, in Swift or Objective-C with usable Swift interop:
1. WiFi pairing
2. preview stream subscription as raw frames or H.264
3. start/stop on-camera recording
4. downloading a recorded video file from the camera to the phone
5. reading current camera state

What is the minimum iOS deployment target?

## Investigation
- Environment: Windows + MinGW64, no Xcode, no Insta360 SDK access. **No empirical inventory was possible from this workstation.**
- Insta360 SDK is gated behind a developer-portal application that requires email approval (typically 1–3 business days). Application not yet submitted.
- Public references skimmed without authoritative download:
  - Insta360 community SDK threads mention an `INSCameraManager` / `INSCameraSDK` umbrella (Objective-C) with Swift interop via bridging header.
  - Reported minimum iOS target in third-party community projects: iOS 13.0 (one source) and iOS 14.0 (another). **Treat both as hearsay** until the SDK README is read.
- The plan (P1-T6 / P3 / P4) uses thin protocol wrappers around the SDK so Swift call-sites are not coupled to Objective-C class names. This isolation is good news regardless of what the SDK looks like.

## Result
Unknown for capabilities (1)–(5). Provisional belief, to be verified:
| # | Capability | Belief | Confidence |
|---|---|---|---|
| 1 | WiFi pairing | Supported via `INSCameraManager` discovery + connect | low (community reports) |
| 2 | Preview stream | Supported, H.264 over WiFi tunnel; raw frame access via decoder block | low |
| 3 | Start/stop recording | Supported via command API | medium (consistently mentioned) |
| 4 | File download from camera | Supported via HTTP-like file API on camera; throughput limited by WiFi | medium |
| 5 | Read camera state (battery, storage, mode) | Supported via state-query API | low |
| - | Min iOS target | iOS 13 or 14 | low |

## Decision (provisional)
Proceed with P1-T6 (`InstaCameraSDK` skeleton) as a **protocol-first Swift wrapper** with the five methods named after the five capabilities above. Implementation bodies remain stubs until the SDK is downloaded and the sample app validates each capability on the real test rig. If any capability turns out to be missing in the real SDK:

- **(1) pairing missing** → architecture change required (we have no plan B; raise with vendor immediately).
- **(2) preview missing** → fall back to A1 mitigation #2 (snapshot polling) wholesale.
- **(3) recording control missing** → user manually triggers record on camera; app records start/stop timestamps only. Documented as degraded mode in demo runbook.
- **(4) file download missing** → user manually offloads SD card after walk; keepsake generation runs in a deferred batch job. Documented as degraded mode.
- **(5) state read missing** → app shows "camera state unknown" badge; pre-flight checklist becomes manual.

**Action required before P1-T6 lands non-stub code:** owner must download SDK, build and run the official sample on the test iPhone with the test camera, confirm each capability, then update this file's status to `confirmed` or `architecture change required` with specifics.

**Revisit date:** 2026-05-09.

## Plan impact
- **P1-T6 (InstaCameraSDK skeleton):** authored against the 5-method protocol regardless. Implementation deferred until A2 closes.
- **P3 walk loop, P4 keepsake:** depend on capabilities (3) and (4) respectively. If either is missing, those phases need a re-design pass.
- **Demo runbook:** must list "tested camera pairing on this exact firmware on this exact phone within last 7 days" as a pre-flight check.
