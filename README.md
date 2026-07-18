# deepiri-flint

**Flint** is Deepiri's stream-native AI worker runtime — the Bun analogue for the event plane.

A single Zig binary: **consume** Sugar Glider streams → **run** a skill (native or WASM) → **publish** results → **ACK**.

## Quick start

```bash
# Zig 0.13+
zig build
zig build test

./zig-out/bin/flint version
./zig-out/bin/flint doctor
./zig-out/bin/flint skills
./zig-out/bin/flint strike document.artifacts document.artifacts.route echo

# Live consumer (needs Sugar Glider)
export FLINT_SUGAR_GLIDER_URL=http://127.0.0.1:8081
export FLINT_TINDER=./tinder.example.json
export FLINT_DRY_RUN=1   # optional: no publish/ack side effects
./zig-out/bin/flint serve
```

## Architecture

```
  document.* / pipeline.* / model-events
              │
              ▼
     ┌─────────────────┐
     │  flint serve    │
     │  bus client ────┼── Sugar Glider /healthz /v1/publish /v1/read /v1/ack
     │  tinder routes  │
     │  skill registry │── native builtins + *.wasm (flint_skill_v1 via wasm3)
     │  ember metrics  │
     └─────────────────┘
```

| Concept | Meaning |
|--------|---------|
| **Strike** | One consume→execute→publish cycle |
| **Skill** | Native builtin or WASM module (`flint_skill_v1`) |
| **Tinder** | JSON map: stream + event_type → skill + publish target |
| **Ember** | In-process counters + last-N strike traces |

## Built-in skills

- `echo` — wrap input with flint metadata
- `passthrough` — republish payload unchanged
- `pressure_tag` — tag `pipeline.pressure.events` for metrics
- `document_fanout` — shape LIS document routes for Helox/inference

## WASM skills (`flint_skill_v1`)

Place `name.wasm` or `name_skill.wasm` under `FLINT_SKILLS_DIR` (default `zig-out/skills`).

Exports:

- `flint_abi_version() -> i32` (=1)
- `flint_on_event(in_ptr:i32, in_len:i32) -> i32` (0=ok)

Imports (`flint` module):

- `host_alloc(size:i32) -> i32`
- `host_set_result(ptr:i32, len:i32)`

Sample: `skills/echo_skill.zig` → `zig-out/skills/echo_skill.wasm`

## Tinder config

See `tinder.example.json`. Env: `FLINT_TINDER=/path/to/tinder.json`.

## Env

| Variable | Default |
|----------|---------|
| `FLINT_SUGAR_GLIDER_URL` | `http://127.0.0.1:8081` |
| `FLINT_SENDER` | `flint` |
| `FLINT_CONSUMER_GROUP` | `flint-workers` |
| `FLINT_CONSUMER_NAME` | `flint-1` |
| `FLINT_SKILLS_DIR` | `zig-out/skills` |
| `FLINT_TINDER` | (built-in defaults) |
| `FLINT_DRY_RUN` | `false` |
| `FLINT_BLOCK_MS` | `2000` |
| `FLINT_READ_COUNT` | `10` |

## License

Proprietary — Team Deepiri. Private repository.  
Vendored [wasm3](https://github.com/wasm3/wasm3) under its MIT license (`vendor/wasm3`).
