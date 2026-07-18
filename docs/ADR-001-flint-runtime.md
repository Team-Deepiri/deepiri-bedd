# Architecture Decision: deepiri-flint

## Context

Deepiri’s AI plane is producer-heavy (Cyrex, LIS, Helox) with Sugar Glider as the
shared Redis Streams transport. We need a **Bun-class** developer experience for
stream workers: single binary, millisecond cold start, language-agnostic skills,
no per-skill Python/Node process tax.

## Decision

Build **Flint** in Zig as a stream-native skill host:

1. Native Sugar Glider HTTP client (`/healthz`, `/readyz`, `/v1/publish`, `/v1/read`, `/v1/ack`)
2. **Tinder** JSON routing: stream + event_type → skill + publish target
3. Skill host:
   - Native builtins (`echo`, `passthrough`, `pressure_tag`, `document_fanout`)
   - WASM skills via vendored **wasm3** (`flint_skill_v1` ABI)
4. **Ember** in-process metrics
5. Honor ModelKit `StreamTopics`
6. Ship as `Team-Deepiri/deepiri-flint` (private)

## Status

Implemented in-repo (v0.2): `flint serve`, `strike`, `doctor`, `skills`, Docker image, CI.

## Consequences

- Positive: one binary for edge + cluster; skills can be written as Zig WASM
- Positive: aligns LIS/Cyrex/Helox bus without duplicating Redis clients
- Negative: WASM skill ABI is a versioned contract (`docs/SKILL_ABI.md`)
- Negative: Zig toolchain learning curve; build with `-Dcpu=baseline` on CI/WSL
