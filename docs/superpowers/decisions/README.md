<!-- docs/superpowers/decisions/README.md -->
# Architecture decisions

Each decision corresponds to one item in spec §9 (`docs/superpowers/specs/2026-05-02-local-gravity-design.md`).

| ID | Title | Status |
|---|---|---|
| A1 | Insta360 preview-stream + onboard recording concurrency | open (provisional, hardware spike pending) |
| A2 | Insta360 iOS SDK feature completeness | open (provisional, SDK download pending) |
| A3 | LLM endpoint reachability at demo venue | mitigation accepted |
| A4 | VLM model selection for outdoor scenes | confirmed |
| A5 | TTS realtime: remote vs on-device | mitigation accepted |
| A6 | Background music / licensing | confirmed |

A1 and A3 are blocking. The others are parallelizable.

See `_spike-closeout.md` for the gate-review summary at end of P0.
