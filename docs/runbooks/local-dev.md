# Local development

```bash
zig build -Dcpu=baseline
export FLINT_SUGAR_GLIDER_URL=http://127.0.0.1:8081
export FLINT_DRY_RUN=1
./zig-out/bin/flint doctor
./zig-out/bin/flint serve
```

Admin: `curl localhost:9108/healthz` and `curl localhost:9108/metrics`
