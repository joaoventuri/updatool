# Changelog

## 0.3.0 — 2026-10-10

- `--source <tar.gz|dir>` for `build` and `ship`: each release builds from a private snapshot taken **after** the deploy lock is held. Fixes the race where two agents extract into one shared source folder and a build ships the other agent's files (or a mix)
- Next.js preset: `presets/nextjs-build.sh` proves the CSS is fresh — a unique marker goes into the global stylesheet and must reach `.next/static`; if the Turbopack cache hands back stale CSS, the cache is wiped and the build runs cold, automatically. `updatool init` installs it as `scripts/build-next.sh`
- Presets: compiler cache mounted with `sharing=locked` (concurrent builds wait instead of writing the same cache)
- Methodology: "a cache must prove it is fresh"

## 0.2.2 — 2026-10-10

- Options are accepted before the command too (`updatool -c app.conf ship`)

## 0.2.1 — 2026-10-10

- Fix: a relative `DOCKERFILE` is resolved inside `CONTEXT` (like `docker build`), not next to `updatool.conf`

## 0.2.0 — 2026-10-10

- `PROXY_TEMPLATE`: keep your own proxy file (routers, middlewares, health checks) and let updatool swap only `{{UPSTREAM}}` — the safe way to adopt updatool on an existing route
- `$UPDATOOL_VERSION`, `$UPDATOOL_SLOT`, `$UPDATOOL_APP`, `$UPDATOOL_BUILT_AT` inside `RUN_ARGS` and `BUILD_ARGS`

## 0.1.0 — 2026-10-10

First public version.

- `ship` / `rollback` with two fixed blue/green slots, atomic route switch, drain, kept slot for instant rollback
- Persistent BuildKit builder with CPU/memory caps; cache presets for Next.js, Node, Python, Go, Rust, Java (Maven/Gradle), Ruby, PHP, .NET
- Pre-build gate (`CHECK_CMD`)
- Kernel-backed deploy lock with holder info; `--expect` race guard; `--no-wait`
- Proxy adapters: Traefik (file provider), Caddy, Nginx, none
- `--json` everywhere, stable exit codes
- `init`, `doctor`, `status`, `history`, `lock`, `logs`, `gc`
- Agent Skill (`skills/updatool/SKILL.md`) for Claude Code, Codex, Cursor and other SKILL.md-compatible agents
- End-to-end test: 3 ships + rollback under continuous load must have zero failed requests
