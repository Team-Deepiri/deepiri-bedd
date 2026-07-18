#!/usr/bin/env bash
set -euo pipefail
BIN="${1:-./zig-out/bin/flint}"
"$BIN" doctor
"$BIN" skills
curl -fsS "http://127.0.0.1:${FLINT_ADMIN_PORT:-9108}/healthz" || echo "admin not up"
curl -fsS "http://127.0.0.1:${FLINT_ADMIN_PORT:-9108}/metrics" || true
