# Changelog

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
