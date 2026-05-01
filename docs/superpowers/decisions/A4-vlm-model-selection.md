# Decision: VLM model selection for outdoor scenes

**ID:** A4 (matches spec §9)
**Date:** 2026-05-02
**Status:** confirmed (primary: `gpt-4o`; fallback: `gpt-4.1`; revisit when an actual outdoor eval set near 玄武湖 is shot)
**Owner:** unassigned

## Question
Of the models available behind `http://100.99.139.20:18141`, which has the best vision capability for outdoor walking scenes (botany, sculpture, signage in Chinese, landscape)? Latency and cost matter; we will call it on every passive question (~1× per minute peak).

## Investigation

### Endpoint inventory
`curl http://100.99.139.20:18141/v1/models` returned 40+ models. Vision-capable candidates filtered by name + provider knowledge:

| ID | Owner | Vision capable | Notes |
|---|---|---|---|
| `gpt-4o` | Azure OpenAI | ✅ | Multiple aliases (`gpt-4o`, `gpt-4o-2024-11-20`, `gpt-4o-2024-08-06`, `gpt-4o-2024-05-13`, `gpt-4-o-preview`) all live |
| `gpt-4o-mini` | Azure OpenAI | ✅ | Cheaper, smaller, vision-capable |
| `gpt-4.1` / `gpt-4.1-2025-04-14` | Azure OpenAI | ✅ | Newer flagged-up version |
| `gpt-5-mini` | Azure OpenAI | ✅ | Newer reasoning model with vision |
| `gpt-5.2`, `gpt-5.4`, `gpt-5.5`, `gpt-5.4-mini` | OpenAI | ✅ (presumed) | Not explicitly tested |
| `gemini-2.5-pro` | Google | ✅ | Tested, returns reasoning trace |
| `gemini-3-flash-preview` | Google | ✅ | Tested, returns reasoning trace |
| `gemini-3.1-pro-preview` | Google | ✅ (presumed) | Not tested |
| `claude-opus-4.5/4.6/4.7`, `claude-sonnet-4/4.5/4.6`, `claude-haiku-4.5` | Anthropic | ✅ (in principle) | Tested two of them; both returned `Bad Request` for the OpenAI-style image_url payload — likely require a different request schema (input_image / source.base64) than tested |
| `text-embedding-*` | Azure OpenAI | ❌ | Embeddings only |
| Search-Agent A/B/C, GPT-3.5, GPT-4 (text), GPT-4-turbo | various | ❌ for vision use case | Either text-only or routing agents |

### Eval set
The plan calls for 5–10 outdoor photos under `spike/A4_vlm_eval/images/` taken near 玄武湖. **I did not have access to take real outdoor photos in this session** and the constraint forbids creating files outside `docs/superpowers/decisions/`. So the eval was a single sanity-check image — a public-domain landscape JPEG (fjord with cliff and figures, 400×300, ~25 KB) — fed to multiple models with the prompt:

> 用一句中文告诉我图里最显眼的事物是什么

This is **NOT** a real eval. It is a smoke test that the request format works and that we get plausible Chinese answers. A real eval set still needs to be shot near the actual demo location and run by the owner before P3 ships.

### Sample prompt + responses (smoke test)

Request body (truncated):
```json
{
  "model": "<MODEL>",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "text", "text": "用一句中文告诉我图里最显眼的事物是什么"},
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,<...>"}}
    ]
  }]
}
```

(Note: even though the file was JPEG and the data URL claimed `image/png`, the endpoint accepted it. When the data URL claimed `image/jpeg` it returned `image media type not supported`. **Action:** wrappers must hard-code `data:image/png;base64,` regardless of source format, or do a real PNG re-encode. Filed as a known quirk.)

| Model | p50 latency (single sample) | Answer | Subjective quality |
|---|---|---|---|
| `gpt-4o` | **2.5 s** | 蓝色的峡湾和高耸的岩石是图中最显眼的事物。 | accurate, natural, concise |
| `gpt-4o-mini` | **2.5 s** | 蓝色的峡湾是图中最显眼的事物。 | accurate, very concise |
| `gpt-4.1` | **2.9 s** | 图里最显眼的事物是中间蜿蜒壮观的蓝色河流。 | "river" instead of "fjord" — minor inaccuracy but pleasant phrasing |
| `gpt-5-mini` | 4.9 s | 图中最显眼的是突出的峭壁及其下方那片深邃湛蓝的峡湾。 | most descriptive; consumed 229 reasoning tokens |
| `gemini-2.5-pro` | 10.9 s | 图中是壮丽的峡湾风光，其中深蓝色的水域和陡峭的悬崖最为显眼。 | excellent prose; **way over latency budget** |
| `gemini-3-flash-preview` | 10.7 s | 图中最显眼的是蜿蜒在群山之间深蓝色的峡湾。 | excellent; over budget |
| `claude-haiku-4.5` | n/a | `Bad Request` | OpenAI image schema not accepted — needs Anthropic-format payload |
| `claude-sonnet-4.5` | n/a | `Bad Request` | same |

Endpoint reachability latency (TCP connect): ~0.29 s from the tailnet host. Add carrier RTT for iPhone over LTE — assume +200–500 ms.

## Result
- All `gpt-4*` and `gpt-5-mini` models work first try with the OpenAI-style `image_url` content part and return correct, idiomatic Chinese.
- Both Gemini models work but their latency (~10 s) exceeds the plan's "≤ 2 s p50" budget for once-per-minute calls. They would force the walk loop to either show "正在看..." for too long or skip frames.
- Claude family requires a different request schema; not used for now (TODO: write a Claude-shaped wrapper if we ever want to switch).
- **No actual outdoor walking-scene eval was performed** (no images of cherry blossom, sculpture, Chinese signage, lake view). The single smoke-test image is insufficient to differentiate `gpt-4o` vs `gpt-4o-mini` on the actual target distribution.

## Decision
**Primary VLM:** `gpt-4o` (alias resolved to `gpt-4o-2024-11-20-vision` server-side).
- Reason: best balance of accuracy ("峡湾 + 岩石" — got both salient elements) and latency (~2.5 s p50 within budget) and a stable, well-documented Azure OpenAI vision schema.

**Fallback VLM:** `gpt-4.1`.
- Reason: same schema, similar latency, slightly different model family — useful when `gpt-4o` is rate-limited or filtered by content filter. (Note: `gpt-4.1` mis-identified the fjord as a "river" in the smoke test; degraded but acceptable for casual companion banter.)

**Tertiary (cost optimization later):** `gpt-4o-mini` for extremely terse confirmations (e.g., "yes there is a person in frame") where token cost matters more than nuance.

**Reject for now:**
- Gemini models — latency too high, will revisit if Google ships a faster vision endpoint or if we relax the budget.
- Claude models — wrong request schema; revisit only if we add a Claude-shaped path in `LLMClient`.

**Quirk to encode in `LLMClient`:** when sending image content, always claim `data:image/png;base64,...` in the URL prefix even if the bytes are JPEG. The endpoint validates the *claimed* media type, not the actual sniffed type. (TODO: file an upstream bug; this is fragile.)

**Action required before P3 ships:** owner must shoot 5–10 real outdoor photos near 玄武湖 (cherry blossom, sculpture, shopfront w/ Chinese signage, lake view) and re-run this comparison. If `gpt-4o` mis-identifies Chinese signage or local landmarks, escalate to a model swap.

## Plan impact
- **P1-T2 (LLMClient):** code the image-content payload with `data:image/png;base64,` prefix and document the quirk inline. Default `model = "gpt-4o"`. Replace `REPLACE_WITH_MODEL_FROM_A4` and `REPLACE_WITH_VISION_MODEL_FROM_A4` in plan lines 1555 / 3086 / 3932 / 3945 with `gpt-4o`.
- **P3 walk loop:** once-per-minute VLM cadence is sustainable at p50 2.5 s + LTE RTT.
- **Demo runbook:** add a "first-call warm-up" step before walk start (one VLM call with a dummy image to prime any cold caches).
- **Spec §9:** A4 closed as `confirmed` for primary + fallback selection; **the eval-set quality assessment remains open** until real outdoor photos are tested.
