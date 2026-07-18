# Changelog

## 0.4.1 — ember
- In-process mock Sugar Glider (`flint demo`) with timed HTTP assembly
- End-to-end integration test: read → strike → publish → ack
- Publish retry + circuit breaker on the serve/strike path
- `flint tinder validate` against known ModelKit topic catalog
- Ember latency histogram buckets exported on `/metrics`

## 0.4.0 — ember
- Real skill logic: redact, fingerprint, schema_gate, training_enrich, artifact_claim, Helox tags, model reload, etc.
- `flint eval` for offline skill execution (`'<json>'` or `@file.json`)
- SIGTERM/SIGINT graceful stop; SIGHUP reloads tinder
- Admin: `/healthz`, `/readyz` (bus probe), `/metrics`, `/skills`, `/version`
- Nested JSON path accessor (`data.documentId`)
- Serve retries with exponential backoff on bus read failures

## 0.3.0 — strike
- Admin HTTP server, DLQ, 15+ builtins, Helm/k8s, example tinder profiles

## 0.2.0
- Sugar Glider HTTP bus client, tinder routing, serve loop, wasm3 skills

## 0.1.0
- Initial scaffold
