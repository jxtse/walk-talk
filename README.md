# walk-talk · 步语 BuYu

> 一个面向 City Walk 场景的「相机 × 多模态 LLM Agent × 语音陪伴」实验项目。
> 由两条平行的实现线组成：iOS 原生 App（`LocalGravity`）与 Windows 桌面 Demo（`demo/`，搭配 Insta360 Link 2 Pro）。

设备端通过云台相机捕捉画面，本地/云端的多模态大模型实时理解所见之物，结合 GPS 轨迹、高德 POI、TTS 与生成式视觉拼贴，最终在散步结束时自动产出一段图文/视频「Keepsake（走步纪念物）」。

---

## 目录结构

| 目录 | 说明 |
|---|---|
| `Sources/LocalGravity/` | iOS App 主模块（Swift Package，后续迁移至 Xcode 项目） |
| `Sources/LocalGravityApp/` | iOS App SwiftUI 入口 |
| `Tests/LocalGravityTests/` | Swift 单元测试 |
| `Resources/` | `Info.plist` / `Secrets.example.plist` 等运行时资源 |
| `demo/` | Windows 端 Python 端到端 Demo（FastAPI + 浏览器前端） |
| `demo_runtime/` | Demo 运行时缓存：keepsake 图片、瞬间快照、moments 等 |
| `insta360_sdk_ref/` | Insta360 Link 2 Pro UVC/PTZ 反向工程参考代码（不参与运行时） |
| `scripts/` | 各能力 smoke test 脚本（高德、相机、TTS、媒体） |
| `docs/` | 设计文档、SDK 接入说明、superpowers 计划与规范 |

---

## 技术栈与技术选型

### 一、iOS 原生端（`LocalGravity` Swift Package）

| 分层 | 选型 | 用途 |
|---|---|---|
| 语言 / 工具链 | **Swift 5.9**, **Swift Package Manager** | 跨 macOS / Windows 协作开发，后续迁移到 Xcode 项目 |
| 最低系统 | **iOS 17 / macOS 14** | SwiftUI + Observation 新特性 |
| UI | **SwiftUI** (`UI/RootView.swift`, `WalkScreen.swift`) | 主界面、分享卡片 |
| 地图 | **MapKit** + **高德 iOS SDK**（`AMapFoundationKit` / `MAMapKit` / `AMapSearchKit`） | 路线绘制、POI 检索、快照 |
| 定位 | **CoreLocation**（`Location/LocationSvc.swift`, `TrackBuffer.swift`） | GPS 轨迹采集与缓冲 |
| 相机 | **Insta360 Camera SDK** (`INSCameraSDK.framework`) + 自研 `CameraBridge` 抽象 + Mock | Insta360 Link 2 Pro 取流 / PTZ |
| 音频 | **AVFoundation** + **Speech**（`Audio/STTService.swift`, `TTSService.swift`, `AudioIO.swift`） | TTS 播报、STT 唤起对话 |
| 网络 | `URLSession` + 自研 `LLMClient` / `DiffusionClient`（`Net/`） | LLM、图像生成、媒体调用 |
| Agent 运行时 | 自研 `AgentRuntime` + `ToolRegistry` + `ProactiveQuota`（`Agent/`） | Tool-use 调度、主动行为节流 |
| Tools | `AmapAroundSearchTool` / `AmapDirectionTool` / `AmapGeoTool` / `AmapTextSearchTool` / `GetCameraFrameTool` / `AnalyzeFrameVLMTool` / `SpeakToUserTool` / `RecordMomentTool` | LLM 可调用工具集 |
| 视频合成 | **AVFoundation** (`AVAssetWriter`) — `Keepsake/Video/` (`VideoAssembler`, `BGMMixer`, `CaptionOverlay`, `ClipExtractor`, `TrackAnimRenderer`) | 散步纪念短片合成 + BGM 混音 + 字幕 |
| 海报合成 | **CoreGraphics** / **CoreImage** (`PosterComposer`, `MapRenderer+Snapshot`) | 静态 keepsake 海报 |
| 会话日志 | `Session/DialogLog.swift`, `MomentLog.swift` | 对话与瞬间持久化 |
| 测试 | **XCTest** | `Tests/LocalGravityTests/` |

### 二、Windows 端 Demo（`demo/`）

面向 Insta360 Link 2 Pro × LLM 的端到端体验验证；浏览器作为 iPhone Mockup 演示界面。

| 分层 | 选型 | 用途 |
|---|---|---|
| 语言 | **Python 3.11+** | Demo 后端 |
| Web 框架 | **FastAPI 0.115** + **Uvicorn 0.32** | HTTP / SSE 推送 |
| 异步与多部分 | `asyncio`, **python-multipart 0.0.12** | 流式事件、文件上传 |
| HTTP 客户端 | **httpx 0.27** | 调用高德 / 远端 LLM / Media 服务 |
| 图像 | **Pillow 10.4** | Keepsake 拼贴、缩放 |
| 相机控制 | **DirectShow** via **pygrabber 0.2** + **comtypes 1.4** + **ffmpeg**（MJPEG 抓取） | Insta360 Link 2 Pro PTZ + 取帧 |
| TTS | **pyttsx3 2.91**（SAPI5） | 离线本地播报 |
| Agent 运行时 | 自研 `demo/agent.py` + `demo/tools.py` | Tool-use 循环、工具注册 |
| Tools | `GetCameraFrameTool` / `AnalyzeFrameVLMTool` / `SpeakToUserTool` / `RecordMomentTool` / `PanCameraTool` / `RecommendNearbyPlaceTool` | 与 iOS 端镜像 |
| LLM / VLM | 远端服务（Tailscale `100.99.139.20:18141`）通过 `demo/llm.py` 适配 | 多模态推理 |
| POI / 路线 | **高德 Web Service API** (`demo/amap.py`) + 预烤数据 (`demo/data/pois_v2.json`, `nanjing_pois.json`) | 周边搜索、路线规划 |
| 剧本回放 | `demo/scripts_player.py` + `demo/data/scenarios/*.json`（companion / jinling / serendipity / prebake） | 离线可重放的演示剧本 |
| 事件总线 | 自研 `EventBus`（`demo/event_bus.py`） + SSE | 前后端实时事件推送 |
| 前端 | 原生 **HTML / CSS / Vanilla JS**（`demo/static/`），iPhone mockup + 多屏热区 | 演示界面 |
| 测试 | **pytest 8.3** + **pytest-asyncio 0.24** | `demo/tests/` 覆盖 agent/工具/事件总线/LLM/keepsake/server |
| 烘焙脚本 | `demo/cli/bake_jinling_assets.py`, `prebake_images.py`, `prebake_pois.py` | 离线预生成素材 |

### 三、Insta360 SDK 参考实现（`insta360_sdk_ref/`）

| 文件 | 平台 | 作用 |
|---|---|---|
| `ptz_server_win.py` | Windows | 可工作的 DirectShow `IAMCameraControl` PTZ HTTP 服务 + ffmpeg MJPEG 抓帧 |
| `ptz_server.py` | macOS | 早期 libusb PTZ HTTP 服务 |
| `probe_insta360_uvc.c` / `uvc_ptz_probe.c` / `uvc_ptz_get.c` / `uvc_ptz_set.c` | macOS | UVC 接口枚举与 PTZ 控制单元探测 |

---

## 第三方服务与密钥

| 服务 | 用途 | 配置位置 |
|---|---|---|
| 高德开放平台 | iOS SDK + Web Service POI / 地理编码 / 路径规划 | `Resources/Secrets.plist`（iOS）/ 环境变量 `AMAP_KEY`（Demo） |
| Insta360 Camera SDK | Link 2 Pro 取流（iOS） | `Frameworks/INSCameraSDK.framework`（迁移到 Xcode 后） |
| 远端 LLM / VLM 服务 | 多模态对话与画面理解 | `demo/config.py` / iOS `Net/Secrets.swift` |

详细接入步骤见 `docs/sdk-setup.md`。

---

## 快速开始

### Windows Demo

```powershell
pip install -r demo/requirements.txt
python -m demo.server
# 浏览器打开 http://127.0.0.1:8788/
```

前置条件：
- Insta360 Link 2 Pro 已连接（DirectShow 名称 `Insta360 Link 2`）
- `ffmpeg` 在 PATH 上，或位于 `C:\ffmpeg\bin\ffmpeg.exe`
- 可访问远端推理服务（默认通过 Tailscale）

### iOS App（SPM 开发模式）

```bash
swift build
swift test
```

迁移到 Xcode 项目时，将 `Sources/LocalGravity/**` 加入 App Target，
并按 `docs/sdk-setup.md` 引入高德与 Insta360 框架、配置 `Info.plist` 权限。

### Smoke 测试

```bash
python scripts/smoke_amap.py
python scripts/smoke_camera.py
python scripts/smoke_media.py
python scripts/smoke_tts.py
```

---

## 设计文档

更深入的需求、规格与实现计划见 `docs/superpowers/`：

- `specs/2026-05-02-link2pro-windows-demo-design.md` — Windows demo 设计
- `plans/2026-05-02-local-gravity-implementation.md` — iOS 实现计划

---

## License

TBD.
