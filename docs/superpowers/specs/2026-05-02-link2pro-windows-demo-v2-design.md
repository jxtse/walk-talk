# 本地引力 / 步语 v2 设计

**日期**：2026-05-02
**状态**：待审

## 1. 目标

在 v1（已上线、12 个 task 实现）基础上加三件事，让 demo 视频更"成片"：

1. **AI 主动控制 PTZ**——不止响应"看一下"，而是在合适的节点自己转头、变焦、环视。
2. **真实高德 POI + 卡片式 UI**——AI 推荐地点时，iPhone 屏幕上弹出卡片（含 AI 预生成的插画、距离/评分、`[去看看] [聊聊它]` 按钮），并显示方向指引。
3. **预设演示模式**——两个完全脚本化的场景（独立于 agent loop），保证 demo 节奏稳定可重放。

视觉上做一次重设计：左边 **iPhone 393×852 mock 框** 装产品 UI，右边 **技术信息面板** 露出摄像头流 + PTZ + 工具调用 + LLM raw + Amap raw，证明系统是真的。

## 2. 总体架构

### 2.1 进程拓扑

```
┌─────────── server.py (FastAPI, port 8788) ───────────┐
│                                                      │
│  /              → static/index.html (新版双面板)     │
│  /video.mjpg    → CameraController.mjpeg_iter()      │
│  /events        → SSE：dialog/moment/ptz/tool/poi/   │
│                       script/llm_raw/amap_raw        │
│  /api/start     → AgentRuntime.handle_user_turn(开)  │
│  /api/say       → AgentRuntime.handle_user_turn(...) │
│  /api/end       → 结束 + 渲染 keepsake               │
│  /api/voice     → POST audio blob → whisper-1 →      │
│                   把转写文字塞进 /api/say 路径        │
│  /api/script/start  → ScriptPlayer.play(scenario_id) │
│  /api/script/stop   → ScriptPlayer.stop()            │
│  /keepsake/{name}   → 静态文件                       │
│  /poi_image/{name}  → 预生成的 POI 卡图              │
└──────────────────────────────────────────────────────┘
```

新增模块：

- `demo/media.py`——`MediaClient`，连 openai-next，封装 `generate_image(prompt, size, save_to)` 和 `transcribe(audio_bytes, mime)`。
- `demo/amap.py`——`AmapClient.search_around(location, keywords, radius)` + `AmapClient.search_text(keywords, city)`，返回归一化 `POI` dataclass。
- `demo/scripts.py`——`ScriptPlayer`，按 timeline 把 event 推到 dialog/moments/ptz/poi/tool 各通道；不调 LLM。
- `demo/data/scenarios/`——两个 JSON 脚本（companion / serendipity）+ `prebake.json`（要预生成的 5 张图清单）。
- `demo/data/pois_real.json`——启动时从 Amap 拉一次缓存下来（避免 demo 时网络抖）。

不变（v1 沿用）：

- `demo/camera.py`、`demo/llm.py`（planner client）、`demo/tts.py`、`demo/dialog.py`、`demo/agent.py`、`demo/keepsake.py`。
- `demo/llm.py` 的 `LLMClient` 仍只负责内部 100.99.139.20:18141 的 chat/vlm；`MediaClient` 是独立的第二个 client，base_url 不同、key 不同、`trust_env=True`（openai-next 是公网）。

### 2.2 SSE 通道扩展

v1 已有 `dialog` / `moment`。v2 在同一个 `/events` 流里加事件 `type` 字段：

| type | payload | 谁发 |
|---|---|---|
| `dialog` | `{role, text, ts}` | dialog log（v1 沿用） |
| `moment` | `{kind, text, image, ts}` | moments log（v1 沿用） |
| `ptz` | `{pan, tilt, zoom, source}` source=agent/script/manual | CameraController.set_position 发布 |
| `tool_call` | `{name, args, result_summary, ts}` | AgentRuntime / ScriptPlayer |
| `llm_raw` | `{phase, model, messages, response}` | LLMClient（debug 模式打开时） |
| `poi_card` | `{poi_id, name, distance, rating, cost, address, image_url, tagline, actions}` | ScriptPlayer / agent recommend |
| `amap_raw` | `{endpoint, params, response}` | AmapClient |
| `script` | `{scenario, step_index, beat_label}` | ScriptPlayer |
| `direction` | `{arrow, distance_m, eta_min, label}` | ScriptPlayer / agent |

前端按 type 分发到不同面板。

## 3. 前端

### 3.1 布局

```
┌──────────────────────── 1280×900 视口 ────────────────────────┐
│                                                               │
│   ┌── iPhone mock (393×852) ──┐    ┌─── 技术面板 (右) ────┐   │
│   │  顶 status bar            │    │  ┌── 演示控制 ──┐    │   │
│   │  ─────────────────────    │    │  │ [场景A] [场景B]    │   │
│   │  对话气泡区（滚动）       │    │  │ [自由模式]         │   │
│   │   AI 气泡 / 用户气泡       │    │  └────────────────┘   │   │
│   │                           │    │  ┌── 摄像头 ────┐    │   │
│   │  POI 卡片浮层（按需）     │    │  │ <img>/video.mjpg│  │   │
│   │  方向指引浮层（按需）     │    │  │ PTZ: pan tilt z │  │   │
│   │  Flash banner             │    │  └────────────────┘   │   │
│   │  keepsake 渲染区          │    │  ┌── 工具调用 (A) ┐   │   │
│   │  ─────────────────────    │    │  │ 时间轴列表         │   │
│   │  输入栏 [文本] [🎙] [送]  │    │  └────────────────┘   │   │
│   │  ─────────────────────    │    │  ┌── LLM raw (B) ─┐   │   │
│   │  [开始散步] [结束]        │    │  │ 折叠/展开          │   │
│   │  底 home indicator        │    │  └────────────────┘   │   │
│   └───────────────────────────┘    │  ┌── Amap raw (C) ┐   │   │
│                                    │  │ 最近一次响应       │   │
│                                    │  └────────────────┘   │   │
│                                    └────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

视觉风格参考 `buyu-demo(3).html`：主色 `#7BC67E`（绿）、卡片 `border-radius: 16px`、气泡左右分明、底部毛玻璃输入栏。深色模式不做。

### 3.2 录音交互

输入框右侧麦克风按钮：

- 默认态：灰色麦克风图标。
- 点击 → 变红、显示波形（用 `MediaRecorder` API），开始录 webm/opus。
- 再次点击 → 停止录音，POST `/api/voice` （`multipart/form-data`，字段 `audio`），等返回的 `text`。
- 拿到 `text` 后**只填入文本框，不自动发送**——用户决定要不要按发送（避免误识别直接发出去）。

### 3.3 POI 卡片

卡片浮在对话区上方（z-index 高于气泡，低于 Flash banner），包含：

- 顶图：预生成插画（`/poi_image/{poi_id}.png`），高 160px，圆角顶部
- 标题：店名
- 子行：`{rating}★ · ¥{cost} · {distance}m · 步行 {eta}min`
- 一段 tagline（脚本里写死，比如"藏在湖边木屋里的独立咖啡"）
- 两个按钮：`[去看看]`（绿）/ `[聊聊它]`（描边）
  - "去看看"→ 卡片缩到角落 + 触发 direction 浮层
  - "聊聊它"→ 把 "聊聊{店名}" 塞进对话当作用户输入（脚本场景里也能塞固定回复）

### 3.4 方向指引

简单浮条横在对话区顶部：`← 100m  步行 1 分钟`，箭头根据 `direction.arrow` 旋转。

## 4. 高德集成

### 4.1 Client

```python
# demo/amap.py
@dataclass
class POI:
    id: str
    name: str
    location: tuple[float, float]   # (lng, lat)
    distance_m: int
    rating: float | None
    cost: float | None
    address: str
    typecode: str
    tags: list[str]                 # from 'atag'
    raw: dict                       # 原始整条，发到 amap_raw SSE
```

`AmapClient(key)`：

- `search_around(location: str, keywords: str, radius: int=2000, offset: int=20) -> list[POI]`
- 每次调用同时通过 `event_bus.publish("amap_raw", {endpoint, params, response_summary})`
- 用 `httpx.Client(timeout=10, trust_env=True)`（高德是公网，需要走代理）

### 4.2 启动期预拉

启动 `server.py` 时 `prebake_pois()` 会查两个固定查询：

1. 玄武湖周边（118.795, 32.075） keywords=`咖啡|甜品|手工冰淇淋|小酒馆`，过滤掉连锁 → 取前 5 条
2. 玄武湖周边 keywords=`鸡鸣寺|玄武湖|紫峰大厦|明孝陵|新街口` 的 text 搜（保留 v1 的几个地标作 fallback）

结果落到 `demo_runtime/cache/pois_real.json`，下次启动若文件存在且 `mtime < 24h` 直接读缓存。

### 4.3 已锁定的 demo POI

脚本场景 B 里硬编码的店：

```json
{
  "poi_id": "beans_solo",
  "name": "Beans Solo 豆号咖啡(玄武湖国展店)",
  "location": [118.787, 32.080],
  "distance_m": 1040,
  "rating": 4.4,
  "cost": 23,
  "address": "玄武湖翠洲门进园 · 芙蓉桥旁",
  "tagline": "藏在湖边木屋里的独立咖啡，靠水那张桌子常常没人",
  "typecode": "050500"
}
```

启动时仍会 amap 实查一次（确认存在 + 拿最新 rating），并 `event_bus.publish("amap_raw", ...)` 让技术面板能看到。

## 5. AI 主动 PTZ

把 `pan_camera` 工具的触发条件从"用户问周围"扩到"任何 LLM 决定看一眼"。变更：

- `prompts.py` 的 SYSTEM_PROMPT 增加 1 条：
  > "**主动看**：当你想引用画面里某个东西、或者想确认方向时，直接调 `pan_camera` 转过去，再调 `analyze_frame_vlm` 确认，再说话。"
- `tools.py` 的 `PanCameraTool` schema 增加 `reason` 字段（必填，例如 `"用户提到湖，先转向湖面"`），方便日志面板看出 AI 意图。
- `agent.py` 在 `_loop` 里把 `pan_camera` 的 `reason` 也写进 dialog log（type=`tool_call`）。

主动行为不在 agent 这层硬编码节奏（节奏交给 ScriptPlayer），但 prompt 改完后，自由模式下 AI 也更愿意自己转镜头。

## 6. 媒体 client（openai-next）

```python
# demo/media.py
DEFAULT_MEDIA_BASE = "https://api.openai-next.com"
DEFAULT_IMAGE_MODEL = "gemini-3.1-flash-image-preview"
DEFAULT_WHISPER_MODEL = "whisper-1"

class MediaClient:
    def __init__(self, *, base_url=DEFAULT_MEDIA_BASE, api_key, timeout=120):
        self._http = httpx.Client(
            base_url=base_url, timeout=timeout,
            headers={"authorization": f"Bearer {api_key}"},
            trust_env=True,   # 公网，需要代理
        )

    def generate_image(self, *, prompt: str, size: str = "1024x1024",
                       save_to: Path) -> Path:
        # 走 /v1/images/generations，模型 gemini-3.1-flash-image-preview
        # response_format=b64_json，写入 save_to
        ...

    def transcribe(self, *, audio_bytes: bytes, mime: str = "audio/webm") -> str:
        # 走 /v1/audio/transcriptions, multipart, model=whisper-1, language=zh
        ...
```

API key 通过环境变量 `OPENAI_NEXT_API_KEY` 注入，开发时 `.env` 文件里写（`.env` 已在 .gitignore）。

## 7. 脚本播放器

### 7.1 数据结构

`demo/data/scenarios/companion.json`：

```json
{
  "scenario_id": "companion",
  "title": "陪伴散步",
  "duration_s": 90,
  "events": [
    {"at": 0.0, "type": "dialog", "role": "ai",
     "text": "早，今天玄武湖风不大，往湖边走走？",
     "speak": true},
    {"at": 8.0, "type": "ptz", "pan": -30, "tilt": 0, "zoom": 100,
     "reason": "脚本：转向湖面"},
    {"at": 8.5, "type": "tool_call", "name": "pan_camera",
     "args": {"direction": "left", "reason": "看湖"}},
    {"at": 12.0, "type": "dialog", "role": "ai",
     "text": "看，对面紫峰大厦还在云里。", "speak": true},
    {"at": 18.0, "type": "dialog", "role": "user",
     "text": "那是什么塔？", "source": "scripted_user"},
    {"at": 19.5, "type": "tool_call", "name": "analyze_frame_vlm",
     "args": {"question": "画面右侧那座塔是什么"}},
    {"at": 22.0, "type": "dialog", "role": "ai",
     "text": "鸡鸣寺的药师塔，南朝四百八十寺剩下的之一。",
     "speak": true},
    {"at": 35.0, "type": "poi_card", "poi_id": "jiming_temple",
     "tagline": "走过去 8 分钟，山门有棵老槐树"},
    {"at": 36.0, "type": "dialog", "role": "ai",
     "text": "要不要绕过去？走过去 8 分钟。", "speak": true},
    {"at": 50.0, "type": "dialog", "role": "user", "text": "记一下"},
    {"at": 51.0, "type": "tool_call", "name": "record_moment",
     "args": {"label": "鸡鸣寺·下次再来"}},
    {"at": 51.5, "type": "moment", "kind": "flash",
     "text": "已记下：鸡鸣寺·下次再来"},
    {"at": 65.0, "type": "dialog", "role": "ai",
     "text": "我转一圈给你看看。", "speak": true},
    {"at": 66.0, "type": "ptz_sweep"},
    {"at": 85.0, "type": "keepsake_render"}
  ]
}
```

`scenarios/serendipity.json`（场景 B，60s）类似结构，关键事件：

- 10s：AI 主动开口 + `poi_card`（beans_solo）+ direction 浮条 `← 100m`
- 25s：用户问"长什么样？"（scripted_user）→ 弹第二张内景图（也是 `poi_card` 的 alt image，或新事件 `image_show`）
- 40s：用户"走吧" → 触发 `direction` 显示 + `ptz` 左转一眼
- 55s：keepsake_render

### 7.2 播放器

```python
# demo/scripts.py
class ScriptPlayer:
    def __init__(self, *, dialog, moments, camera, tts, event_bus, root: Path):
        ...
        self._task: threading.Thread | None = None
        self._stop = threading.Event()

    def play(self, scenario_id: str) -> None:
        # 加载 JSON，启动后台线程，按 at 排序，sleep 到点执行 _dispatch(ev)
        # 同时发 script SSE：{scenario, step_index, beat_label}
        ...

    def stop(self) -> None: ...

    def _dispatch(self, ev: dict) -> None:
        # 路由到对应 channel
        # type=dialog -> dialog.append + (speak ? tts.say)
        # type=ptz -> camera.set_position
        # type=ptz_sweep -> camera.sweep()
        # type=tool_call -> event_bus.publish('tool_call', ...)
        # type=poi_card -> event_bus.publish('poi_card', merged_with_prebake)
        # type=moment -> moments.append
        # type=keepsake_render -> 调 keepsake.render(session)
        # type=direction -> event_bus.publish('direction', ...)
```

播放期间：

- 不调用 LLM，不调用 Amap（POI 从 prebake 缓存里 merge）。
- 不阻断 `/api/say`——用户仍可以打字/录音。但脚本里所有 `role: user, source: scripted_user` 的事件不会等真人输入。
- 自由模式按钮按下后，`ScriptPlayer.stop()` 立刻停。

## 8. 图片预生成

### 8.1 清单（5 张）

`demo/data/scenarios/prebake.json`：

```json
[
  {"id": "jiming_temple_card",
   "size": "1024x1024",
   "prompt": "中国南京鸡鸣寺，黄墙琉璃顶，秋天上午雾气，远景，水墨与水彩结合的插画风格，柔和日光，竖幅构图"},
  {"id": "companion_keepsake",
   "size": "1024x1536",
   "prompt": "玄武湖晨走的散步收藏卡，湖边、塔影、一杯咖啡，文艺散步剪贴风，柔和米色背景，留白可写字"},
  {"id": "beans_solo_storefront",
   "size": "1024x1024",
   "prompt": "玄武湖边一家小木屋独立咖啡馆门面，店招写'Beans Solo'，临湖窗，夏末傍晚柔光，文艺纪实摄影"},
  {"id": "beans_solo_interior",
   "size": "1024x1024",
   "prompt": "Beans Solo 咖啡馆室内，木桌木椅，靠窗座位能看到湖面波光，吧台后咖啡师在做手冲，温暖灯光"},
  {"id": "serendipity_keepsake",
   "size": "1024x1536",
   "prompt": "一次小小的偶遇——湖边咖啡店明信片，店面剪影、一杯拉花、印章式日期，文艺散步剪贴风，竖幅"}
]
```

### 8.2 流程

`demo/scripts/prebake_images.py` 独立 CLI：

```
python -m demo.scripts.prebake_images
```

- 读 `prebake.json`，对每条调 `MediaClient.generate_image`，结果保存到 `demo_runtime/cache/images/{id}.png`。
- 已存在则跳过（除非 `--force`）。
- 失败重试 3 次（gemini 偶尔 429）。
- 输出表格：id / 状态 / 文件大小 / 用时。

`server.py` 启动时检查这 5 张是否齐全，缺哪张就直接报错退出（避免 demo 中途挂）。

`/poi_image/{name}` 路由从这个目录服务。

## 9. Whisper 语音

### 9.1 前端

```js
// app.js 新增
const recorder = new MediaRecorder(stream, {mimeType: 'audio/webm;codecs=opus'});
// 点击麦 → start; 再次点击 → stop;
// onstop: blob → fetch('/api/voice', {method:'POST', body: formData})
//         → text 填入输入框
```

### 9.2 后端

```python
@app.post("/api/voice")
async def voice(audio: UploadFile):
    data = await audio.read()
    text = await asyncio.to_thread(
        media_client.transcribe,
        audio_bytes=data, mime=audio.content_type or "audio/webm",
    )
    return {"text": text}
```

不自动触发 `/api/say`——前端拿到文本后让用户决定（也可改）。

## 10. 配置 / 环境

`.env`（示例文件 `.env.example` 进 git，真值不进）：

```
AMAP_KEY=ff287a156a20b1b95830b719d6c6a047
OPENAI_NEXT_API_KEY=sk-...
PLANNER_BASE_URL=http://100.99.139.20:18141
```

`server.py` 启动顺序：

1. 读 .env（用 `os.environ.get` + 简易 .env 加载，不引 python-dotenv）
2. 构造 LLMClient / MediaClient / AmapClient
3. `prebake_pois()` + 校验图片缓存
4. 启动 CameraController
5. 起 FastAPI

## 11. 错误与降级

| 失败 | 行为 |
|---|---|
| openai-next 调不通（图片预生成阶段） | CLI 报错退出，要求手动重试或 `--skip-images`（会让对应 POI 卡显示占位灰图） |
| Amap 失败 | 用 `pois_real.json` 缓存；都没有就退化到 v1 的 `nanjing_pois.json` |
| Whisper 失败 | 前端 toast "语音识别失败，请打字" |
| 摄像头掉线 | 沿用 v1：agent 返回"我没看清"；脚本里 ptz/sweep 事件 try/except 吞掉 |
| 脚本播放中相机已被自由模式占用 | 启动场景前若检测到自由 agent 正在 `_loop`，弹错并 abort |

## 12. 测试

只对新增模块写 pytest（不动 v1）：

- `tests/test_amap.py`：mock httpx 响应，断 POI 解析
- `tests/test_media.py`：mock httpx，断 generate_image 写文件 / transcribe 解析返回
- `tests/test_scripts.py`：注入假 dialog/moments/camera/tts/event_bus，跑场景 A 前 20s（用 `time_warp=10` 加速），断事件序列
- `tests/test_server_voice.py`：FastAPI TestClient，mock MediaClient，跑 `/api/voice`

烟囱脚本 `scripts/smoke_media.py`：跑一次真实 gemini 图生（10s 内成功就 OK）+ 真实 whisper 转写（用本地一个 1s wav）。

## 13. 不做（YAGNI）

- 真实导航：`[去看看]` 按钮只触发 direction 浮条 + 把镜头转一下，不接高德路径规划。
- 多 session 并发：仍单实例。
- 用户账号 / 持久化：每次启动新 session，`demo_runtime` 自己删。
- 图片生成放在 demo 期间实时调（确认走预生成）。
- 第二个场景的真实 agent 对接（场景 B 全脚本）。

## 14. 开放问题（设计阶段全部已解）

无。
