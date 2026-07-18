# Architecture Decision: deepiri-flint

## Context

Deepiri’s AI plane is producer-heavy (Cyrex, LIS, Helox) with Sugar Glider as the
shared Redis Streams transport. We need a **Bun-class** developer experience for
stream workers: single binary, millisecond cold start, language-agnostic skills,
no per-skill Python/Node process tax.

## Decision

Build **Flint** in Zig as a stream-native skill host:

1. Native Sugar Glider HTTP/gRPC client
2. WASM skill ABI (`flint_skill_v1`) for hot-loaded transforms / light inference glue
3. Honor ModelKit `StreamTopics` (`document.*`, `pipeline.*`, `model-events`, …)
4. Ship as `Team-Deepiri/deepiri-flint` (private)

## Consequences

- Positive: one binary for edge + cluster; skills can be written in any WASM-capable language
- Positive: aligns LIS/Cyrex/Helox bus without duplicating Redis clients
- Negative: WASM skill ABI is a new contract to version
- Negative: Zig toolchain learning curve for contributors
