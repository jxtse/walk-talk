# Demo Runbook v2 (≈3 min recording)

## Pre-flight (一次性)

1. `.env` 已存在且填了 `AMAP_KEY` / `OPENAI_NEXT_API_KEY`
   （参考 `.env.example`）
2. 摄像头插好；`tasklist | findstr python` 没有遗留 python
3. Tailscale 连上；`curl http://100.99.139.20:18141/v1/models` 正常
4. 浏览器允许麦克风（首次开 8788 会弹权限）
5. OBS / Win+G 准备好录浏览器窗口 + 系统音

## 一次性预生成（首装时跑一次；之后缓存即可）

```
python -m demo.cli.prebake_images   # ~1-2 min, 5 张图
python -m demo.cli.prebake_pois     # ~5s, 1 个缓存文件
```

## 启动

```
python -m demo.server
```

等 `demo server up: http://127.0.0.1:8788/`，浏览器全屏打开。

## 录制脚本（≈3 min）

### 段 1：场景 A 陪伴（90s）
1. 开始录像
2. 右侧点 "▶ 场景 A · 陪伴"
3. 跟着脚本看：AI 自动主动开口 → 转向湖 → 用户问"那是什么塔" →
   AI 调 VLM → POI 卡片（鸡鸣寺）→ 记一下 → 环视 → keepsake

### 段 2：场景 B 偶遇（60s）
4. 点 "▶ 场景 B · 偶遇"
5. AI 主动推荐 Beans Solo → POI 卡片 + 方向浮条 → 用户问"长什么样" →
   卡片图换成内景 → 用户"走吧" → keepsake

### 段 3：自由模式真演（30s）
6. 点 "⌨ 自由模式"
7. 点麦克风说一句"周围有什么"，松手等转写 → 按发送 → 看真实 AI 反应

8. 停止录像

总长 ≈ 3 min。

## 出错恢复
- 摄像头帧停：忽略，AI 会说"我没看清"
- LLM 超时：等或重启 server，重录
- 脚本卡住：右上角 "■ 停止脚本"

## 重录
每次录完删 `demo_runtime/`（保留 `cache/`，那里是预生成的图和 POI）。

```
rm -rf demo_runtime/keepsake_*.png demo_runtime/moments
```

cache 不删，下次启动秒开。
