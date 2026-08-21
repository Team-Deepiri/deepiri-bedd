# Contributing

1. Use Zig 0.13+
2. `zig build test -Dcpu=baseline`
3. Prefer small commits with conventional messages (`feat:`, `fix:`, `docs:`)
4. Skills must not open Redis — use the bus client only via Bedd host
5. Update `docs/SKILL_ABI.md` if you change WASM imports/exports

## Branches & releases

- Open PRs from `feature/*`/`fix/*` branches into `dev`. `ci.yml` (build/test/smoke) and
  `codeql.yml` run there.
- Promote `dev` to `main` via PR when ready to ship. Since that code already passed CI on
  `dev`, the promotion PR skips re-running build/test/smoke and CodeQL.
- To cut a release, bump the top of `CHANGELOG.md` with a new `## X.Y.Z` heading as part of
  the `dev` -> `main` PR. Once merged, `release.yml` tags `vX.Y.Z`, builds the image, and
  publishes it to `ghcr.io/team-deepiri/bedd:X.Y.Z` (+ `:latest`), with a GitHub Release
  generated from that CHANGELOG section. If the top version isn't bumped, the merge to
  `main` is a no-op for releases (no duplicate tag/image).
