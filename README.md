# deepiri-flint

**Flint** is Deepiri's stream-native AI worker runtime — the Bun analogue for the event plane.

Where Bun is a fast single-binary JS runtime, Flint is a fast single-binary **stream → skill → stream** runtime written in Zig: consume Sugar Glider / Redis Streams, run hot-loaded WASM skills (embedding, extract, splice, pressure), publish typed results back onto the Deepiri bus.

## Why

Deepiri already has producers (Cyrex, LIS, Helox) and a bus (Sugar Glider + Synapse + ModelKit topics). What we lack is a **tiny, cold-start-cheap worker host** that:

1. Speaks the bus natively (no Python/Node sidecar tax per skill)
2. Loads skills as WASM (safe, language-agnostic, hot-reloadable)
3. Fits edge / laptop / k8s sidecars equally well
4. Is boringly reliable (Zig: no GC pauses, explicit allocators, static linking)

## Name

**Flint** — the spark that starts the fire. One strike (binary) → flame (skill execution) on the Deepiri stream plane.

## Architecture (v0)

```
  document.* / pipeline.* / model-events
              │
              ▼
     ┌─────────────────┐
     │  flint daemon   │  Zig single binary
     │  ┌───────────┐  │
     │  │ bus client│◄─┼── Sugar Glider HTTP (/v1/publish,/v1/read,/v1/ack)
     │  └─────┬─────┘  │
     │        ▼        │
     │  ┌───────────┐  │
     │  │ skill vm  │  │  WASM plugins (WASI)
     │  └─────┬─────┘  │
     │        ▼        │
     │  ┌───────────┐  │
     │  │ publish   │──┼──→ inference-events / document.artifacts / …
     │  └───────────┘  │
     └─────────────────┘
```

### Core concepts

| Concept | Meaning |
|--------|---------|
| **Strike** | One consume→execute→publish cycle |
| **Skill** | WASM module implementing `flint_skill_v1` ABI |
| **Tinder** | Config that maps stream + event_type → skill |
| **Ember** | In-process metrics / last-N strike traces |

### Skill ABI (sketch)

Skills export:

- `flint_skill_name() -> ptr/len`
- `flint_skill_on_event(ptr, len) -> status` (JSON in/out via linear memory)

Flint owns HTTP to Sugar Glider; skills never touch Redis.

## Novel vs existing stack

| Piece | Role | Flint role |
|-------|------|------------|
| Cyrex | AGI orchestration / training emission | Upstream producer |
| Helox | Training runtime | Upstream consumer |
| LIS | Document intelligence | Upstream producer (`document.*`) |
| Sugar Glider | Bus sidecar | Transport Flint speaks |
| ModelKit | Topics + schemas | Contracts Flint honors |
| **Flint** | **Local skill host** | **New** — Bun-for-streams |

## Roadmap

- **v0 (this repo):** binary scaffold, config, bus client stub, `flint strike` dry-run, CI + CodeQL
- **v1:** real Sugar Glider HTTP client + one sample WASM skill (echo / JSON transform)
- **v2:** consumer groups, ACK, DLQ, skill hot-reload
- **v3:** optional llama.cpp / ONNX host plugins for edge inference strikes

## Build

```bash
# Zig 0.13+
zig build
./zig-out/bin/flint --help
```

## License

Proprietary — Team Deepiri. Private repository.
