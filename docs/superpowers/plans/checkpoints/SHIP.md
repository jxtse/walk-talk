# SHIP — Ship-Readiness Gate

**Task:** P6-T7
**Purpose:** A single document evaluator (演示者 / 团队 lead) signs off before tagging `ready-to-demo`. Each spec §11 success criterion has an evidence pointer. **Gating rule per the brief:** this checklist itself ships when `walks/walk-3.md` exists with `Keepsake overall ≥ 3/5` marked. Real-walk numbers are filled in by the user.

> **Do not** tag `ready-to-demo` while any row is `FAIL` or `UNVERIFIED` against a hard criterion. Soft criteria (marked ⚠) may ship with caveats — record the caveat.

---

## 1. Spec §11 success-criteria evidence table

| # | §11 criterion | Evidence pointer | Pass condition | Status (PASS / FAIL / UNVERIFIED) | Notes |
|---|---|---|---|---|---|
| 1 | **可运行** — 玄武湖完整 30 分钟散步全程无崩溃 | `plans/checkpoints/walks/walk-3.md` §4 (Crashes / hangs) | empty list | | |
| 2 | **AI 不烦人** — 主动开口 ≤ 9 次 / 30 分钟 | `walks/walk-3.md` §2 (Last proactive utterance / total proactive) | total ≤ (demo-min ÷ 10) × 3 | | |
| 3 | **被动有问必答** | `walks/walk-3.md` §4 (Passive Q&A — answered well) | answered well ≥ 80% of asked | | |
| 4 | **纪念品有冲击力** — 评委首次看会"哇" | `walks/walk-3.md` §3 (Keepsake overall 1–5) | ≥ 3 (gate); ≥ 4 ideal | | |
| 5 | **降级稳健** — 拔网线 / 关相机不翻车 | `walks/walk-2.md` §4 (Leg A/B/C results) + `plans/checkpoints/P5-closeout.md` (video→poster fallback) | all three legs PASS | | |
| 6 | **影石特色明显** — 360° 镜头语言可被识别 | `walks/walk-3.md` §3 (360° clip recognizability) + 一名外部评估者主观打分（记录姓名） | ≥ 3 / 5 + evaluator name on file | | evaluator: ____ |

---

## 2. Process gates (independent of walk numbers)

| Item | Evidence pointer | Pass condition | Status |
|---|---|---|---|
| 所有 P0–P5 close-out tags 存在 | `git tag` 输出含 `p0-done` … `p5-done` | all six present | |
| `P6-bugs.md` 中 `severity: blocker` 全部 `resolved` | `plans/checkpoints/P6-bugs.md` §Resolved | 0 open blockers | |
| 单元 + 集成测试套件全绿 | `xcodebuild test -scheme LocalGravity` 最近输出 | exit 0 | |
| Demo 主路径已彩排 ≥ 3 次 | `demo/demo-script.md` "演练记录" 表 | ≥ 3 行已填 | |
| Demo 降级路径已彩排 ≥ 3 次 | `demo/degradation-script.md` "演练记录" 表 | ≥ 3 行已填 | |
| Handout 一页纸已最终化（联系方式填全） | `demo/handout.md` "联系我们" 表 | 无 `____` 占位 | |
| 备播视频文件齐 | `demo/assets/walk-3-keepsake.mp4` + `walk-2-keepsake.mp4` 存在 | 两个文件均可播放 | |

---

## 3. Soft criteria (⚠ — may ship with caveat)

| Item | Notes / Caveat |
|---|---|
| ⚠ 配乐版权来源（spec §9.6）已确认 | source: ____ |
| ⚠ 演示现场网络备案（手机热点 + 投屏方案）已就位 | plan: ____ |
| ⚠ Backup demo 设备（第二台手机或第二台相机）已携带 | yes / no |

---

## 4. Sign-off

- [ ] §1 所有 6 行 = PASS（或第 4 行 = 3 且评估者明确接受）
- [ ] §2 所有 7 行 = PASS
- [ ] §3 所有 ⚠ 行已记录或接受 caveat
- [ ] `walks/walk-3.md` 存在且 `Keepsake overall ≥ 3/5` 已勾选 — **本 gate 的最低必要条件**

**Signed by:** ____________________   **Date:** ____________

**Verdict:** GO / NO-GO

---

## 5. If NO-GO

1. 标注上面表格中所有 FAIL 行。
2. 对每个 FAIL 在 `P6-bugs.md` 新建 `severity: blocker` 条目。
3. 修复后回到 P6-T2 流程：写测试、修、提交、标记 resolved。
4. 重跑必要的 walk（一般是 walk-3 全程；若仅降级失败可重跑 walk-2 + walk-3 中受影响段落）。
5. 重新走完本 gate。

**禁止操作：**
- ❌ 跳过 fail 直接 tag `ready-to-demo`
- ❌ 在 demo 当天才补打 tag（`ready-to-demo` 必须在 demo 前 ≥ 24 小时存在）

---

## 6. Tag commands (only after GO)

```bash
git add docs/superpowers/plans/checkpoints/SHIP.md
git commit -m "docs(p6): ship-readiness verified — all §11 criteria met"
git tag ready-to-demo
```
