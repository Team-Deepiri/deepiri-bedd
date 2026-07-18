# Bedd runtime image — Bun-style, not a platform microservice.
#
# Use it like oven/bun:
#   FROM ghcr.io/team-deepiri/bedd:0.6 AS bedd
#   …
#   COPY --from=bedd /usr/local/bin/bedd /usr/local/bin/bedd
#
# Or as a base when the container's job is stream skill work:
#   FROM ghcr.io/team-deepiri/bedd:0.6
#   COPY tinder.json /etc/bedd/tinder.json
#   ENV BEDD_TINDER=/etc/bedd/tinder.json BEDD_BUS_URL=http://synapse-sidecar:8081
#   CMD ["bedd", "serve"]

FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends curl xz-utils ca-certificates \
  && rm -rf /var/lib/apt/lists/*
ARG ZIG_VERSION=0.13.0
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
  | tar -xJ -C /opt \
  && ln -s /opt/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig
WORKDIR /src
COPY . .
RUN zig build -Doptimize=ReleaseSafe -Dcpu=baseline

# Runtime: bedd on PATH (like bun). Default CMD is the CLI, not a forever-service assumption.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/zig-out/bin/bedd /usr/local/bin/bedd
COPY --from=build /src/zig-out/skills /opt/bedd/skills
COPY tinder.example.json /opt/bedd/tinder.example.json
ENV BEDD_SKILLS_DIR=/opt/bedd/skills
ENV PATH="/usr/local/bin:${PATH}"
# Bun defaults to `bun` REPL/help; we default to help so this image is a toolkit.
ENTRYPOINT ["bedd"]
CMD ["help"]
