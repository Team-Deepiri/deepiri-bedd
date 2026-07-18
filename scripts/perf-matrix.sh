#!/usr/bin/env bash
# Multi-dimension Bedd perf matrix → markdown + JSON for PR comments.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${BEDD_BIN:-$ROOT/zig-out/bin/bedd}"
OUT_DIR="${1:-$ROOT/bench-out}"
mkdir -p "$OUT_DIR"

if [[ ! -x "$BIN" ]]; then
  echo "missing bedd binary at $BIN — run: zig build -Doptimize=ReleaseSafe -Dcpu=baseline" >&2
  exit 1
fi

run_one() {
  local name="$1" n="$2" skills="$3"
  local json="$OUT_DIR/${name}.json"
  echo "==> $name (n=$n skills=$skills)"
  "$BIN" bench --iterations "$n" --skills "$skills" --json | tee "$json"
}

run_one echo_50 50 echo
run_one mix_50 50 echo,redact,fingerprint
run_one mix_200 200 echo,redact,fingerprint
run_one redact_100 100 redact

python3 - <<'PY' "$OUT_DIR"
import json, sys, pathlib
out = pathlib.Path(sys.argv[1])
rows = []
for p in sorted(out.glob("*.json")):
    rows.append(json.loads(p.read_text()))
md = ["## Bedd perf matrix", "", "| run | n | ok | err% | thr/s | mean ms | p50 | p95 | p99 |", "|-----|---|----|------|-------|---------|-----|-----|-----|"]
for r in rows:
    name = p.name if False else ""
    lat = r["latency_ms"]
    md.append(
        f"| {r.get('_name', '')} | {r['iterations']} | {r['ok']} | {r['error_rate_pct']:.2f} | {r['throughput_per_s']:.1f} | {lat['mean']:.2f} | {lat['p50']} | {lat['p95']} | {lat['p99']} |"
    )
# fix names from files
md = ["## Bedd perf matrix (mock bus)", "",
      "| run | n | ok | err% | thr/s | mean ms | p50 | p95 | p99 |",
      "|-----|---|----|------|-------|---------|-----|-----|-----|"]
for p in sorted(out.glob("*.json")):
    r = json.loads(p.read_text())
    lat = r["latency_ms"]
    md.append(
        f"| `{p.stem}` | {r['iterations']} | {r['ok']} | {r['error_rate_pct']:.2f} | {r['throughput_per_s']:.1f} | {lat['mean']:.2f} | {lat['p50']} | {lat['p95']} | {lat['p99']} |"
    )
verdict = "Bedd mock-bus path is healthy for integration experiments." if all(r['error_rate_pct'] < 5 for r in [json.loads(p.read_text()) for p in out.glob('*.json')]) else "Bedd mock-bus shows elevated errors — investigate before host integration."
md += ["", f"**Verdict (mock):** {verdict}", "",
       "_Host-bus comparison (with vs without Bedd on Sugar Glider) belongs in the platform integration PR._"]
(out / "REPORT.md").write_text("\n".join(md) + "\n")
print((out / "REPORT.md").read_text())
PY
