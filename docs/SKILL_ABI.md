# Skill ABI — flint_skill_v1

Skills never talk to Redis. Flint owns the Sugar Glider HTTP client.

## Exports

| Symbol | Signature | Notes |
|--------|-----------|-------|
| `flint_abi_version` | `() -> i32` | Must return `1` |
| `flint_on_event` | `(in_ptr:i32, in_len:i32) -> i32` | `0` = success |

Input JSON is written into linear memory at `in_ptr` for `in_len` bytes.

## Imports (`flint` module)

| Symbol | Signature | Notes |
|--------|-----------|-------|
| `host_alloc` | `(size:i32) -> i32` | Bump allocator in linear memory; `0` = failure |
| `host_set_result` | `(ptr:i32, len:i32)` | Set JSON result buffer for the host |

## Native builtins

Same logical contract via Zig `SkillFn` in `src/skill/mod.zig`.
