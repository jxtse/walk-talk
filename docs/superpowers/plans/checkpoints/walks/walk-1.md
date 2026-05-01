# Walk #1 — Happy-path full session

**Task:** P6-T1
**Goal:** Run the full 30-minute happy-path walk at 玄武湖 to surface bugs and confirm the main loop end-to-end.
**Owner:** <fill in>
**Date / start time:** YYYY-MM-DD HH:MM
**Weather / lighting:** <e.g. 晴, 22°C, 下午光线柔和>
**Route:** <one-line description, e.g. "玄武门入 → 环洲 → 樱洲 → 梁洲 → 玄武门出">

> Templates below are to be **filled in by the user during/after the walk**. Do not skip the pre-flight checklist.

---

## 1. Pre-flight checklist (T-15 min)

Tick each item. **If any item fails, stop and fix before walking** — observations from a half-prepared walk are not actionable.

### Hardware
- [ ] Insta360 相机电量 ≥ 80%
- [ ] Insta360 microSD 卡剩余空间 ≥ 32 GB
- [ ] Insta360 与手机已配对，预览流可见（per A1 outcome）
- [ ] Insta360 录制模式确认（按 P0-T1 spike 选定的模式：360 / 单镜头 / ___）
- [ ] iPhone 电量 ≥ 80%；低电量模式关闭
- [ ] 蓝牙耳机电量 ≥ 80%；与手机配对成功；播放/麦克风双向通；佩戴舒适
- [ ] 备用充电宝 ≥ 50%

### Network
- [ ] Tailscale / 选定 VPN 已连接，状态绿色
- [ ] LLM endpoint ping OK：`http://100.99.139.20:18141` `/v1/models` 返回 200
- [ ] 高德 API key 有效；`amap_around_search` 试调一次返回结果
- [ ] 蜂窝数据信号 ≥ 3 格

### App
- [ ] 最新构建已安装（git sha: `__________`）
- [ ] 麦克风、相机、定位、蓝牙四项系统权限已授予
- [ ] 后台音频模式开启（耳机锁屏可继续 STT/TTS）
- [ ] 主动配额计数器初始为 0（启动后首次 walk）
- [ ] 上次会话残留已清除（`.idle` 状态确认）

### Logistics
- [ ] 衣着合适，能把手机完全装进口袋
- [ ] 现场录制者（朋友 / 自拍杆）就位（用于第三方视角佐证 demo 视频，可选）
- [ ] 计时器 / stopwatch 准备就绪（手表或副机）
- [ ] `walk-1.md` 已在副机/纸笔上预先打开，便于即时记录

---

## 2. During-walk script (30 min)

> Walk naturally. Don't perform. Do **at least** these interactions, distributed across the 30 min:

| 类别 | 目标次数 | 触发台词建议（自然即可） |
|---|---|---|
| 被动 Q&A（视觉问答）| ≥ 5 | "嘿，那是什么花？" / "前面那个建筑是什么？" / "这棵树看着像啥？" |
| 主动推荐接受 | ≥ 1 | （等 AI 主动开口推荐 POI 时）"好啊，带我过去" |
| 主动推荐拒绝 | ≥ 1 | "换一个" 或 "不去了" |
| 被动捕捉 record_moment | ≥ 1 | "记一下我刚才说的那个想法" |
| 方向指引 | ≥ 1 | "带我去湖那边" |
| 静默时段 | ≥ 5 min | 不说话，观察 AI 是否真的闭嘴 |

**结束触发**："散步结束" 或在 App 中点击 [TAP] End。等待纪念品生成完成。

---

## 3. Stopwatch beats (fill in)

| 事件 | 时间戳 (mm:ss from walk start) | 备注 |
|---|---|---|
| App 启动 → 进入 walking 状态 | | |
| 第 1 次 AI 主动开口 | | 推荐内容： |
| 第 2 次 AI 主动开口 | | |
| 第 3 次 AI 主动开口 | | |
| 第 1 次被动 Q&A 提问 → AI 回答完毕 | | 端到端延迟 ____ s |
| 第 1 次 record_moment 触发 → 静默确认 | | 端到端 ____ s |
| "散步结束" 说出 → 状态切到 ending | | |
| 纪念品生成开始 | | |
| 纪念品生成完成 | | 总时长 ____ s |

---

## 4. Observations (fill in)

```markdown
# Walk 1 — YYYY-MM-DD HH:MM
- Duration (actual): __ min
- Proactive utterances total: __ (target ≤ 9 over 30 min)
  - of which: recommendations accepted __ / rejected __
- Passive Q&A: asked __, answered __, "我没看清"兜底 __
- record_moment triggered: __ times (intended __)
- Latency complaints: <list timestamps + what felt slow>
- Crashes / hangs / freezes: <list>
- Camera dropouts: <list timestamps + duration>
- GPS drift / loss: <list>
- Audio glitches (TTS clipped, STT mishears): <list>
- Keepsake produced: yes / no
  - kind: video | poster
  - duration / size: __ s / __ MB
  - perceived quality (1–5): __
  - 360° clip recognizable: yes / no
- Battery drain: phone __ %, camera __ %
- Bugs filed (ids): BUG-P6-___, BUG-P6-___
```

---

## 5. Observation rubric (1–5 scoring guide)

Fill in `perceived quality` above using this rubric:

| Score | Keepsake quality |
|---|---|
| **5** | "想发朋友圈" — 评委首次看到会"哇"，剪辑节奏合理，海报能看出散步主题，360° 镜头语言清晰 |
| **4** | 完整可分享，但有一两处小瑕疵（字幕错位 / 配乐稍突兀 / 海报勉强相关） |
| **3** | 能看，但平淡。代表"达到 ship 阈值"。降级长图也可给 3 |
| **2** | 有明显问题（视频卡顿 / 海报与散步无关 / 字幕错乱），分享会被问"这是啥" |
| **1** | 不可用 / 失败 / 仅占位 |

**Ship gate (per spec §11):** walk-3 quality ≥ 3. Walk-1 / walk-2 quality 仅作参考。

---

## 6. Post-walk actions

- [ ] Step 4 (per plan): file each bug into `../P6-bugs.md` with severity. Use schema there.
- [ ] If any **blocker**: do NOT schedule walk-2 yet — proceed to P6-T2 first.
- [ ] Step 5: commit walk-1.md + P6-bugs.md updates with message `docs(p6): walk 1 observations + bug list`.
- [ ] Save raw artifacts (video file from camera, app log, screen recording if any) to `~/walk-talk-walks/walk-1/` (gitignored — local only).

---

## 7. Sign-off

- [ ] Walked: _______________  Date: _______________
- [ ] Bugs filed in P6-bugs.md (count): __
- [ ] Blocker count: __
- [ ] Ready for P6-T2: yes / no
