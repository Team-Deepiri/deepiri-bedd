# Install Bedd (Bun-style)

Bedd is a **runtime/CLI**, not a platform microservice. Think `bun`, not `redis`.

## Local

```bash
# from a checkout with Zig 0.13
./install.sh
# or
zig build -Doptimize=ReleaseSafe -Dcpu=baseline
export PATH="$PWD/zig-out/bin:$PATH"
bedd version
bedd bench --iterations 20 --json
```

## Docker — copy binary into YOUR image

```dockerfile
# multi-stage: build or pull Bedd runtime, then copy into Cyrex / Helox / LIS / worker
FROM ghcr.io/team-deepiri/bedd:0.6 AS bedd

FROM your-service-base
COPY --from=bedd /usr/local/bin/bedd /usr/local/bin/bedd
# optional sample skills
COPY --from=bedd /opt/bedd/skills /opt/bedd/skills
ENV BEDD_SKILLS_DIR=/opt/bedd/skills
# Host owns routes + bus URL:
# ENV BEDD_BUS_URL=http://synapse-sidecar:8081
# ENV BEDD_TINDER=/app/tinder.json
# If this container's job is stream skills:
# CMD ["bedd", "serve"]
```

## What not to do

- Do **not** add a separate `deepiri-bedd` compose service next to Sugar Glider.
- Do **not** treat Bedd as a peer of Cyrex/Helox/LIS — those own business consumers; Bedd is the tool a worker process may run.

## CLI surface (like bun run / bun test)

| Command | Role |
|---------|------|
| `bedd serve` | long-running consume→skill→publish loop |
| `bedd eval` | one-shot skill (offline) |
| `bedd strike` | dry-run one route |
| `bedd bench` | mock-bus perf matrix |
| `bedd doctor` | env + bus probe |
| `bedd tinder validate` | route schema check |
