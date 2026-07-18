# On-call

| Symptom | Check |
|---------|-------|
| strikes_err rising | DLQ `pipeline.dead-letter`, skill logs |
| bus unreachable | Sugar Glider `/readyz`, Redis |
| no progress | consumer group lag, tinder routes |
| wasm load fail | `FLINT_SKILLS_DIR`, ABI version |
