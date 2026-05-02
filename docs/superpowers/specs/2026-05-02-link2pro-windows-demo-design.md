# Demo Prototype: Insta360 Link 2 Pro × Walk-Talk on Windows

**Date:** 2026-05-02
**Status:** design — pending implementation plan
**Owner:** xjx
**Target output:** a self-contained Windows desktop application that can run end-to-end on the dev box (Insta360 Link 2 Pro plugged via USB) so that a 3-minute screen recording can be produced for jury review. **iOS app is out of scope for this milestone.**

---

## 1. Why this exists

The original LocalGravity (walk-talk) plan assumes:
- iPhone runs the Swift app
- Insta360 camera connects via the official iOS SDK over WiFi
- User actually walks outdoors

Two of those three assumptions are blocked or risky right now:
1. The Insta360 iOS SDK has not been validated end-to-end (decision A2 is still open).
2. The dev workstation is Windows; no Mac toolchain is available locally.

But we already have, on Windows:
- Verified PTZ control of the Link 2 Pro via DirectShow `IAMCameraControl` (`ptz_server_win.py`)
- Verified MJPEG video pipe via `ffmpeg -f dshow`
- Network access to the internal LLM endpoint at `http://100.99.139.20:18141`

The cheapest path to a demoable artifact is to **rebuild the agent loop in Python on Windows**, point it at the Link 2 Pro on the desk, and use it to record a screen-capture demo. The Swift architecture serves as the design template, not the codebase.

---

## 2. Scope

### In scope
- A single Python service running on Windows that:
  1. Owns the Insta360 Link 2 Pro (PTZ control + MJPEG video)
  2. Runs an LLM-driven ReAct agent loop against the internal endpoint
  3. Exposes a browser UI showing the live camera feed, dialog log, and agent activity
  4. Speaks AI replies via system TTS (Windows SAPI)
  5. Accepts user voice input via a "push to talk" button (browser → server → Whisper-compatible STT) **OR** typed input — whichever is faster to ship; see §6
  6. Generates a simplified keepsake (5 selected frames + dialog quotes, optionally with BGM) at session end

### Out of scope (explicit)
- iOS app, Swift code, real GPS, real outdoor walking
- Live high-quota Amap calls (we use a frozen JSON dataset of 6 Nanjing POIs)
- Diffusion-generated keepsake poster (a static template-rendered collage is enough)
- Multi-user, auth, persistence beyond a single session
- Production-grade error recovery beyond "log it and keep going"

---

## 3. The demo flow this is designed to enable

A ~3 minute recorded video, room-scale, camera on the desk, narrator at the keyboard:

| Time | Event |
|---|---|
| 0:00 | User clicks "开始散步"; AI greets, suggests "我们就在玄武湖走一圈吧" |
| 0:30 | User says/types "嘿，那是什么？" while pointing PTZ at a desk object → agent calls `analyze_frame_vlm` → speaks answer |
| 1:00 | Agent proactively says "前面 200 米有座鸡鸣寺，要不要绕过去？" (from frozen POI data) |
| 1:30 | User says "记一下，下次想再来" → `record_moment` triggers, UI flashes |
| 2:00 | Agent calls `pan_camera` to sweep the room ("让我看看周围") — Link 2 Pro hero shot |
| 2:30 | User says "散步结束" → keepsake renders: 5 key frames + dialog quotes collage |
| 3:00 | Done |

This is the script the prototype must support. Anything not on this list can be cut.

---

## 4. Architecture

```
┌────────────────────── Windows host ──────────────────────┐
│                                                          │
│  Browser UI (single page, served by FastAPI)             │
│   ├─ live MJPEG <img>                                    │
│   ├─ dialog log (event-stream)                           │
│   ├─ user input box + "push to talk" button              │
│   └─ keepsake panel                                      │
│              │                                           │
│              ▼ HTTP / SSE                                │
│  ┌──────────────── FastAPI app ─────────────────────┐    │
│  │                                                  │    │
│  │  HTTP routes:                                    │    │
│  │   GET /                  → UI                    │    │
│  │   GET /video.mjpg        → MJPEG passthrough     │    │
│  │   GET /events            → SSE: agent events     │    │
│  │   POST /api/say          → user text input       │    │
│  │   POST /api/start        → start a "walk"        │    │
│  │   POST /api/end          → end + render keepsake │    │
│  │   GET /keepsake/<id>.png → keepsake image        │    │
│  │                                                  │    │
│  │  Singletons:                                     │    │
│  │   - CameraController (PTZ + frame window)        │    │
│  │   - AgentRuntime      (ReAct loop + tool reg)    │    │
│  │   - DialogLog         (turn-by-turn record)      │    │
│  │   - MomentLog         (record_moment events)     │    │
│  │   - TTSService        (Windows SAPI)             │    │
│  │   - KeepsakeBuilder   (collage renderer)         │    │
│  └──────────────────────────────────────────────────┘    │
│              │                                           │
│              ▼ requests                                  │
│  Internal LLM endpoint (Tailscale)                       │
│  http://100.99.139.20:18141/v1/chat/completions          │
│   - planner: claude-sonnet-4.5                           │
│   - VLM:     gemini-2.5-pro (or gpt-4o)                  │
│              │                                           │
│              ▼ USB                                       │
│  Insta360 Link 2 Pro                                     │
│   - DirectShow IAMCameraControl (PTZ)                    │
│   - dshow → ffmpeg → MJPEG pipe                          │
└──────────────────────────────────────────────────────────┘
```

### Components and their boundaries

**`CameraController`** — sole owner of the camera. Wraps everything currently in `ptz_server_win.py`:
- A PTZ worker thread (owns COM init)
- A camera worker thread (owns ffmpeg subprocess + MJPEG demux)
- A `FrameWindow` (last 5 minutes of decoded JPEG bytes with timestamps)
- Public API: `position()`, `set_position(pan, tilt, zoom)`, `move(dir, step)`, `latest_frame()`, `frame_at(timestamp)`, `mjpeg_iter()`

**`AgentRuntime`** — runs the ReAct loop. One agent instance per session.
- `start(user_message)` — kicks off a turn
- Internally: build messages → call LLM with tool schemas → if tool_calls, dispatch → loop until model emits a final assistant message → emit `assistant.say` event
- Hard cap on iterations (e.g. 8 tool calls per user turn) to avoid runaway

**`ToolRegistry`** — 5 tools:
1. `get_camera_frame()` → `{image_b64, captured_at}`
2. `analyze_frame_vlm(question)` → calls VLM with current frame + question, returns text
3. `speak_to_user(text)` → enqueues TTS, also emits `assistant.say` event
4. `record_moment(label)` → snapshots current frame + writes to `MomentLog`
5. `pan_camera(direction, degrees)` — direction ∈ left/right/up/down, value in degrees; calls `CameraController.move`. Includes a `sweep_room` convenience direction that scripts a slow left → right → center motion.

(Plus a sixth optional: `recommend_nearby_place()` → reads from frozen `data/nanjing_pois.json` and returns one POI not yet recommended. This is what powers the "前面有座鸡鸣寺" beat.)

**`DialogLog`** — append-only list of `{role, text, timestamp}`. Powers the SSE event stream and the keepsake quote selector.

**`MomentLog`** — append-only list of `{label, timestamp, frame_path}` triggered by `record_moment`.

**`TTSService`** — wraps `pyttsx3` (which uses Windows SAPI). Async, doesn't block the agent loop.

**`KeepsakeBuilder`** — at end of session: pick 5 frames (the moments + 2 frames at 0:30 and 2:00), pick 5–8 dialog quotes (LLM-driven or simple heuristic — TBD §6), render a 1080×1920 portrait collage with PIL.

### Threading model
- HTTP server: FastAPI default thread pool
- Camera PTZ: 1 dedicated COM-init thread, queue-based
- Camera ffmpeg pipe: 1 dedicated I/O thread
- Agent loop: spawned per user turn on FastAPI's executor; only one active at a time per session (queue if needed)
- TTS: pyttsx3's own thread

No async/await mixing with COM. No threading inside the agent loop — we keep it sequential and dispatch tools synchronously.

---

## 5. Data flow for one user turn

User says "嘿，那是什么？" (typed or transcribed):

1. Browser POSTs `/api/say {text: "嘿，那是什么？"}`
2. FastAPI appends to `DialogLog`, emits `user.say` SSE event, and submits an agent turn
3. `AgentRuntime` builds messages: system prompt + dialog history + this user message
4. Calls LLM with the 6 tool schemas
5. LLM responds with `tool_calls: [{name: "analyze_frame_vlm", args: {question: "用户问那是什么"}}]`
6. Runtime dispatches:
   - `analyze_frame_vlm` calls `CameraController.latest_frame()` → base64s it → POSTs to VLM model with the question
   - VLM returns "看起来是一株散尾葵..."
7. Tool result fed back to LLM
8. LLM emits final message with `tool_calls: [{name: "speak_to_user", args: {text: "看起来是一株散尾葵..."}}]`
9. `speak_to_user` appends to `DialogLog`, emits `assistant.say` SSE, queues TTS
10. Agent loop terminates (no more tool calls)
11. Browser sees event, updates dialog log; speakers play TTS

Proactive turns (the "前面 200 米..." beat at 1:00) are triggered by a simple timer thread that fires every 60 seconds during a session and asks the agent "你认为现在该不该说点什么？" — the agent decides whether to call `recommend_nearby_place` + `speak_to_user` or stay silent. **No quota class for v1; if it talks too much, we tune the prompt.**

---

## 6. Open decisions left for the implementation plan

These are deliberately deferred from this design — the plan author should pick:

1. **User input modality:** typed only? or typed + push-to-talk via Whisper? Whisper adds ~1 day of work and adds polish to the recording.
   - Default if not chosen: **typed only**, but with prominent text input that scripted demo lines can be pasted into.

2. **Keepsake quote selection:** LLM call ("pick 5 dialog turns that best summarize this walk") vs. heuristic ("first user turn, last user turn, all `record_moment` triggers")?
   - Default: **heuristic**. Simpler, faster, deterministic for re-shoots.

3. **Proactive timer interval & jitter:** every 60s? every 45–90s with jitter?
   - Default: **fixed 60s**.

4. **Model choice for planner:** `claude-sonnet-4.5` vs. `claude-haiku-4.5` vs. `gpt-4o`?
   - Default: **claude-sonnet-4.5** — fast enough, follows tool instructions reliably.

5. **Model choice for VLM:** `gemini-2.5-pro` vs. `gpt-4o`?
   - Default: **gpt-4o** — empirically more reliable for "describe this image" with Chinese output.

---

## 7. File structure

```
walk-talk/
├── ptz_server_win.py            # existing, kept as standalone reference
├── demo/                        # NEW — everything for this milestone
│   ├── server.py                # FastAPI entry point
│   ├── camera.py                # CameraController (extracted from ptz_server_win)
│   ├── agent.py                 # AgentRuntime + ReAct loop
│   ├── tools.py                 # 6 tools, each a small class
│   ├── llm.py                   # OpenAI-compatible client wrapper
│   ├── tts.py                   # pyttsx3 wrapper
│   ├── keepsake.py              # PIL collage builder
│   ├── dialog.py                # DialogLog + MomentLog
│   ├── prompts.py               # system prompt + proactive prompt
│   ├── data/
│   │   └── nanjing_pois.json    # frozen 6 POIs (玄武湖 / 鸡鸣寺 / 紫峰 / 明孝陵 / 夫子庙 / 新街口)
│   ├── static/
│   │   ├── index.html           # single-page UI
│   │   └── app.js
│   └── README.md                # how to run, how to record demo
├── docs/superpowers/specs/2026-05-02-link2pro-windows-demo-design.md  # this file
└── ...
```

The existing `ptz_server_win.py` stays as a working reference and quick smoke-test entry point. `demo/camera.py` is a refactor of its camera logic into a class with a cleaner API, no behavior change.

---

## 8. Out-of-scope failure modes (acknowledged but not handled)

- LLM endpoint goes down mid-demo → demo aborts; we re-record
- Camera unplugged mid-demo → camera worker logs error and reconnects; agent gets `no_frame` from `get_camera_frame` and is told to apologize. Not pretty but doesn't crash.
- Tool produces bad JSON → agent gets a `{"error": "..."}` and decides what to do; we don't try to repair LLM output

---

## 9. Definition of done

- `python demo/server.py` starts cleanly on the Windows dev box with the camera plugged in
- Browser at `http://127.0.0.1:8788/` shows live video and a working dialog UI
- The 7-step script in §3 can be walked through in one continuous session and produces:
  - A live audio response from the agent (heard via speakers)
  - At least one `record_moment` UI flash
  - At least one `pan_camera`-driven physical camera movement
  - A keepsake PNG saved to disk with 5 frames + 5–8 dialog quotes
- One full screen-capture recording of the above exists at `demo/recordings/<date>.mp4`
