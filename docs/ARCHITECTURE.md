# Architecture

Flint is a single binary worker:

1. **Bus** — Sugar Glider HTTP
2. **Tinder** — route table
3. **Skills** — native or WASM
4. **Ember** — metrics
5. **Admin** — `/healthz`, `/metrics`

See ADRs under `docs/adr/`.
