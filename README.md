<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img alt="updatool" src="assets/logo-light.svg" width="420">
  </picture>
</p>

<p align="center">
  <b>Build fast. Ship without downtime. Let your AI agents deploy safely.</b><br>
  A tiny, language-agnostic deploy tool and method for single-server and small fleets — blue/green slots,<br>
  incremental builds, a real deploy lock, and machine-readable output built for humans <i>and</i> agents.
</p>

<p align="center">
  <a href="tests/e2e.sh"><img alt="e2e: 0 failed requests" src="https://img.shields.io/badge/e2e-0%20failed%20requests-10B981"></a>
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-10B981">
  <img alt="Bash 4.4+" src="https://img.shields.io/badge/bash-4.4%2B-3B82F6">
  <img alt="Any language" src="https://img.shields.io/badge/stack-any%20language-111C33">
  <a href="skills/updatool/SKILL.md"><img alt="Agent Skill" src="https://img.shields.io/badge/Agent%20Skill-Claude%20%C2%B7%20Codex%20%C2%B7%20Cursor-8B5CF6"></a>
</p>

<p align="center"><a href="README.pt-BR.md">Português</a> · <a href="docs/METHODOLOGY.md">The method</a> · <a href="skills/updatool/SKILL.md">Agent skill</a></p>

---

```console
$ updatool ship
ship shop a1b2c3d → e4f5a6b
▸ checks: npm run typecheck && npm test
✔ checks passed
▸ build shop:e4f5a6b
✔ built shop:e4f5a6b in 38s          # warm cache: only what changed is rebuilt
▸ start shop-green (e4f5a6b)
✔ shop-green is healthy
▸ switch traffic → shop-green
✔ traffic is on shop-green
▸ drain 5s, then stop shop-blue (kept for rollback)
✔ shipped e4f5a6b on shop-green (61s)
```

## Why

Most teams that self-host end up with one of two deploys:

- **"docker compose up -d"** — simple, but every deploy restarts the app: requests fail for 5–30 s.
- **A platform** (Kubernetes, a PaaS dashboard) — zero downtime, but a lot of machinery for one or two servers.

And then the everyday pains show up:

| Pain | What updatool does |
|---|---|
| A one-line change rebuilds everything (minutes) | Persistent BuildKit builder + cache presets per language → **seconds** |
| Type checks/tests run *inside* the image build, every time | A **gate** (`CHECK_CMD`) runs before the build; the image build stays incremental |
| Deploy = restart = errors for users | **Two fixed slots** (blue/green): health first, one atomic route switch, drain, done |
| Rollback means rebuilding the old version | The previous slot is **kept stopped** → `updatool rollback` in seconds |
| Two people (or two AI agents) deploy at once and overwrite each other | A **kernel-backed lock** (`flock`) + `--expect <version>` race guard |
| A build on the production host starves the live app | **CPU/memory-capped** builder (`BUILD_CPUS`, `BUILD_MEMORY`) |
| You already run Traefik / Caddy / Nginx | updatool **writes a route file** for the proxy you have — nothing new to adopt |
| Agents can't read human logs reliably | **`--json` on every command** + stable exit codes |

## How it works

```
             ┌────────────── updatool ship ──────────────┐
  git push → │ lock → check → build (cache) → start idle │
             │ slot → health → switch route → drain →    │
             │ stop old slot (kept for rollback) → unlock│
             └───────────────────────────────────────────┘

   users ──► proxy (Traefik | Caddy | Nginx) ──► app-green  ✔ live (new)
                                             ╲
                                              ► app-blue   ◼ stopped (instant rollback)
```

Production is only touched in **one** step — the route switch — and only after the new slot answered its health check. If anything fails before that, users never notice; if the public check fails after it, updatool switches back on its own.

## Quickstart

```bash
# 1. install (on the server)
curl -fsSL https://raw.githubusercontent.com/joaoventuri/updatool/main/install.sh | sh

# 2. in your project
updatool init        # detects the stack, writes updatool.conf (+ a cache-ready Dockerfile)
updatool doctor      # checks docker, buildx, network, proxy, cache mounts
updatool ship        # check → build → blue/green → done
```

Minimal `updatool.conf` behind Traefik:

```bash
APP=shop
PORT=3000
HEALTH_PATH=/health
NETWORK=web
PROXY=traefik
TRAEFIK_FILE=/opt/traefik/dynamic/shop.yml
TRAEFIK_RULE='Host(`shop.example.com`)'
TRAEFIK_ENTRYPOINTS=websecure
TRAEFIK_CERTRESOLVER=letsencrypt
CHECK_CMD="npm run typecheck && npm test"
BUILD_CPUS=2
```

All keys: [`presets/updatool.conf.example`](presets/updatool.conf.example) · proxies: [docs/proxies.md](docs/proxies.md) · moving an existing app: [docs/adopting.md](docs/adopting.md)

## Commands

| Command | What it does |
|---|---|
| `updatool init` | Detects the stack and writes `updatool.conf` (+ a cache-ready Dockerfile if you have none) |
| `updatool doctor` | Checks docker, buildx, flock, network, proxy and whether your Dockerfile uses cache mounts |
| `updatool check` | Runs the gate (`CHECK_CMD`) only |
| `updatool build` | Builds with the persistent cache, no traffic change |
| `updatool ship` | The full flow. `--expect <live>` · `--skip-checks` · `--skip-build` · `--no-wait` · `--force` |
| `updatool rollback` | Starts the kept slot, health, switch back, stop the bad one |
| `updatool status` | Live slot/version, rollback target, lock holder |
| `updatool history` | Last ships and rollbacks (who, when, how long) |
| `updatool lock` | Who holds the deploy lock right now |
| `updatool logs` | Follows the live slot |
| `updatool gc` | Removes old images (keeps both slots + `KEEP_RELEASES`), trims the build cache |

Every command accepts `--json`. Exit codes are a contract: [docs/exit-codes.md](docs/exit-codes.md).

## Any language

updatool ships **containers**, so the language doesn't matter. What changes per stack is *where the build cache lives* — that's what [`presets/`](presets) encodes:

| Stack | Cached between builds |
|---|---|
| Next.js | npm cache, type check moved to the gate, fresh-CSS proof (`nextjs-build.sh`); Turbopack disk cache **off** (stale CSS in ~1/3 of builds, measured) |
| Node | `~/.npm` (pnpm store / yarn cache variants in the file) |
| Python | `~/.cache/pip` (or `~/.cache/uv`) |
| Go | module cache + `~/.cache/go-build` |
| Rust | cargo registry + `target/` |
| Java | `~/.m2` (Maven) · `~/.gradle` (Gradle) |
| Ruby | bundler cache + `tmp/cache` for assets |
| PHP | Composer cache |
| .NET | NuGet packages |

## Built for AI agents

updatool ships with an **[Agent Skill](skills/updatool/SKILL.md)** (the open `SKILL.md` format read by Claude Code, Codex, Cursor, Gemini CLI and others). It teaches an agent to deploy *like a careful senior engineer*:

1. `updatool status --json` first — never ship blind.
2. `updatool ship --expect <live_version> --json` — if someone shipped meanwhile, it stops (exit `9`).
3. Exit `75` (locked) → wait or report the holder; **never** break someone else's deploy.
4. Exit `3/4/5` → production untouched; read the log path in the JSON and fix.
5. Rollback is one command and takes seconds.

```bash
# Claude Code (project)          # Codex (project)
mkdir -p .claude/skills           # mkdir -p .agents/skills
cp -r /usr/local/lib/updatool/skills/updatool .claude/skills/   # …or .agents/skills/
```

## Real numbers

Measured on a production Next.js 16 app (≈90 routes, 4 vCPU VM shared with the live app):

| | Before | With updatool's method |
|---|---|---|
| Image build, one-line change | ~236 s | **~40 s** (compile 150 s → 5 s; type check moved to the gate) |
| Traffic switch | ~150 s (recreate + double switch) | **~20–30 s** (one switch, old slot kept) |
| Requests failed during 6 back-to-back switches under load | — | **0 of 2,504** |
| Rollback | rebuild the old commit (~7 min) | **seconds** |

## How it compares

| | updatool | Kamal 2 | Coolify | Dokploy | `compose up -d` |
|---|---|---|---|---|---|
| Zero-downtime switch | ✅ | ✅ | ✅ (not for Compose) | ✅ (Swarm) | ❌ |
| Keeps your existing proxy | ✅ Traefik/Caddy/Nginx | ❌ kamal-proxy | ❌ its own | ❌ its own | ✅ |
| Needs a registry | ❌ (build on host) | ✅ | ❌ | ❌ | ❌ |
| Incremental build presets | ✅ | ❌ | ❌ | ❌ | ❌ |
| Deploy lock + race guard | ✅ | partial (lock) | ❌ | ❌ | ❌ |
| One-command instant rollback | ✅ (slot kept) | ✅ | ✅ | ✅ | ❌ |
| Agent skill + JSON contract | ✅ | ❌ | ❌ | ❌ | ❌ |
| Server footprint | 0 daemons | proxy | ~0.5–2 GB | ~0.5 GB | 0 |

updatool is intentionally small: no dashboard, no cluster, no agent on the server — a Bash CLI, two containers and the proxy you already trust. If you need multi-region autoscaling, use Kubernetes.

## The method

The tool is the easy part; the rules are what make deploys boring. Read **[The updatool method](docs/METHODOLOGY.md)** — eight principles you can apply with or without this tool.

## Development

```bash
bash tests/unit.sh     # pure helpers, no Docker
bash tests/e2e.sh      # real Docker + Traefik: 3 ships + rollback under load ⇒ 0 failures
```

Last e2e run (Docker 28, Traefik 3.4): 3 ships + 1 rollback under 8 parallel clients —
**1,480 requests, 0 failures**; `--expect` mismatch → exit 9; busy lock → exit 75;
unhealthy release → exit 5 with traffic kept on the good version.

## License

[MIT](LICENSE)
