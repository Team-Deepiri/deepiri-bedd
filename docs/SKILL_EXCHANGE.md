# Skill exchange

Bedd routes **skills**, not message storage. The bus (Redis Streams / HTTP) still holds events.

## Binding fields

| Field | Meaning |
|-------|---------|
| `exchange` | `direct` \| `topic` \| `headers` \| `fanout` |
| `event_type` / `routing_key` | Match key (`*` / `word.*` / `#` for topic) |
| `headers` | `k=v,k2=v2` for headers exchange |
| `skill` | One skill or chain `redact,fingerprint` |
| `recovery_skill` | On failure, try this before DLQ |
| `confirm` | After publish success, emit confirm (if enabled) |
| `publish_stream` / `publish_event_type` | Output |

## Env

| Var | Default | Meaning |
|-----|---------|---------|
| `BEDD_PREFETCH` | `READ_COUNT` | Max entries per read; weighted by skill cost |
| `BEDD_LEAN` | false | Publish raw skill output (no wrap envelope) |
| `BEDD_CONFIRMS` | true | Emit confirms when binding `confirm: true` |
| `BEDD_CONFIRM_STREAM` | `bedd.confirms` | Confirm stream name |
| `BEDD_DLQ_STREAM` | `dead-letter` | Dead-letter stream |

## Topic patterns

- `*` — one word
- `#` — zero or more words
- words separated by `.`
