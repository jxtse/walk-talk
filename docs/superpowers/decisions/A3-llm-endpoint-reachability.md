# Decision: LLM endpoint reachability at demo venue

**ID:** A3 (matches spec §9)
**Date:** 2026-05-02
**Status:** mitigation accepted (Tailscale-on-hotspot primary + public-internet backup; revisit at venue dry-run no later than T-7 days)
**Owner:** unassigned (whoever holds the demo phone)

## Question
How will the demo phone reach `http://100.99.139.20:18141` from the venue WiFi or carrier network? Tailscale on the phone? A public reverse proxy? A backup endpoint?

## Investigation
- The address `100.99.139.20` is in the 100.64.0.0/10 CGNAT block, which is what Tailscale uses for its WireGuard mesh. **Confirmed: the LLM endpoint is on a Tailscale tailnet, not on the public internet.** Any device that can reach it must be a member of the same tailnet.
- Reachability test from this Windows workstation (which is already on the tailnet):
  - `curl http://100.99.139.20:18141/v1/models` → HTTP 200 in ~0.76 s (full body), TCP connect ~0.29 s. Endpoint is alive and serves an OpenAI-compatible `/v1/models` listing of ~40 models (Claude, GPT, Gemini, embeddings, search agents).
- Endpoint behaviour:
  - Plain HTTP, no auth header observed in the simple GET request.
  - OpenAI-compatible chat-completions API confirmed end-to-end (see A4 for sample call + response).
  - No SSL/TLS — the security perimeter is the tailnet itself.
- Reachability has **not yet been tested from an iPhone over LTE** in this session (no iPhone available). That test must be done before the first end-to-end walk demo. Tailscale's iOS client supports the same 100.x address space.
- Demo venue: assumed unknown / hostile WiFi (conference WiFi often blocks UDP, breaks captive portals, etc.). Tailscale uses UDP-over-WireGuard with a TCP/HTTPS DERP relay fallback; in practice it survives most conference networks but can fail in highly restrictive corporate guest WiFi.

## Result
- The endpoint is **only reachable via the tailnet.** No public DNS resolves to `100.99.139.20`.
- From the tailnet on a wired host: works, fast, no auth.
- From an iPhone with Tailscale installed and signed in to the same tailnet: **expected to work**, untested in this session.
- From an iPhone without Tailscale: **will not work.**

## Decision
**Primary path (path A):** install Tailscale on the demo iPhone, log in to the same tailnet, and use the iPhone's own LTE hotspot (or LTE directly) for backhaul. This makes the demo independent of the venue WiFi entirely. Configuration toggle in the app:

```
LG_LLM_BASE_URL=http://100.99.139.20:18141
```

**Backup path (path C):** keep a second OpenAI-compatible endpoint configured (Volcengine Ark / Azure OpenAI / one of the public-internet models that the same router exposes — e.g., a Cloudflare-hosted reverse proxy of a small VLM). Switch by env var or build flag at app launch:

```
LG_LLM_BASE_URL=https://backup-llm.example.com/v1   # backup, public internet, requires API key
LG_LLM_API_KEY=sk-...                               # only set when using backup
```

The app's `LLMClient` reads both env vars at init; if `LG_LLM_API_KEY` is non-empty, it sends `Authorization: Bearer ...` headers, otherwise it goes header-less (tailnet path).

**Path B (public reverse proxy of the tailnet endpoint)** is rejected for now: it would expose an unauthenticated endpoint to the public internet, which is unacceptable. If we later need it, gate behind Cloudflare Access with a service-token header.

**Pre-demo checklist additions:**
- T-7 days: dry-run from demo iPhone over LTE — `curl /v1/models` must succeed in <2 s.
- T-1 day: dry-run from demo iPhone on demo-venue WiFi (if accessible) — same test.
- T-0: keep Tailscale running with "Always-on VPN" enabled, hotspot ready as fallback.

**Revisit date:** T-7 days before any public demo (re-test from the actual demo phone on the actual carrier).

## Plan impact
- **P1-T2 / P1-T3 (LLMClient):** must accept both `LG_LLM_BASE_URL` and `LG_LLM_API_KEY` from env / Info.plist. Header is conditional on key presence.
- **P3 walk loop:** must surface "LLM unreachable" gracefully — fall back to a canned cheerful line ("路上风景挺好，咱们继续走") and queue the question for retry. Already noted in plan.
- **Demo runbook:** add the two pre-demo `curl` tests and the "Tailscale Always-on" requirement.
- **Spec §9:** A3 closed as `mitigation accepted` (not `confirmed`, because we have not yet validated from the actual demo iPhone on the actual demo network).
