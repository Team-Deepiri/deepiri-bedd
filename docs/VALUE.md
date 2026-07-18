# When Bedd helps (and when it does not)

## Helps
- **Skill exchange:** topic / headers / fanout / direct bindings that route *skills* on your existing streams
- **Chains + recovery:** `redact,drop_fields` with `recovery_skill` before DLQ
- **Filter path:** `bedd filter` / `bedd eval` inside a worker (no extra consumer group)
- **Direct Redis serve:** `BEDD_BUS_URL=redis://…` without an HTTP hop
- **Portable skills:** one binary + WASM ABI across Alpine/Debian workers

## Does not help
- Embedding the binary without invoking it
- Replacing your bus — Bedd is the skill plane, not message storage
- Trivial one-liner transforms already in-process in the hot path

## Verdict method
Compare the same workload with vs without Bedd filter / serve on the skill-exchange bindings you actually need.
