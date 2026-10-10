# The updatool method

Eight rules for shipping software to production fast, without downtime, with
several people — and several AI agents — deploying the same app. They come from
real incidents; updatool just makes them the default.

---

## 1. Build where the cache lives

A build should only redo what changed. Containers make this easy to lose: an
ephemeral builder throws away the dependency cache and the framework's compile
cache every time, so a one-line fix costs a full cold build.

- Use a **persistent builder** (updatool creates one BuildKit builder per host and keeps it).
- Put package-manager and compiler caches in **`RUN --mount=type=cache`** (see `presets/`).
- Order the Dockerfile from least to most volatile: lockfile → install → source → build.

> Measured: a Next.js build went from 236 s to 40 s with no code change — only the cache.

## 2. Check before you build, not inside the build

Type checks, linters and tests are *gates*, not *artifacts*. Running them inside
`docker build` repeats them on every image and makes the build slower than it
needs to be.

- Run them once, as `CHECK_CMD`, **before** the build. A failure stops the ship
  with exit `3` and nothing else happens.
- Never skip the gate because the build is "only a small change" — that is
  exactly when people ship broken code.

## 3. One ship at a time

Two deploys at once is how a good release disappears: B builds from an older
base and overwrites A's work, and nobody notices until a user does.

- A **lock per app**, held by the kernel (`flock`): released automatically if
  the process dies, so it never goes stale.
- The lock tells you **who** holds it (user, host, version, since). Wait or ask;
  never break it.
- **`--expect <live version>`**: the ship only happens if production is still
  what you saw. If someone shipped meanwhile, you rebase and try again (exit `9`).

## 4. Two slots, one switch

Blue/green, done literally: two fixed containers, `app-blue` and `app-green`.

- The new version goes into the **idle** slot. Production is not touched yet.
- Traffic moves with **one atomic route write** (temp file + rename) and the
  proxy's own graceful reload. No "recreate the main container and switch back".
- The old slot is **stopped, not removed** — it is your rollback.

## 5. Health before traffic, drain before stop

- The new slot must answer `HEALTH_PATH` (2xx/3xx) before it gets a single request.
  A health endpoint should check what the app needs to serve (DB reachable,
  config loaded), not just "the process is up".
- After the switch, keep the old slot running for `DRAIN_SECONDS` so in-flight
  requests finish; then stop it with a graceful timeout (`SIGTERM`, then `SIGKILL`).
- Apps should handle `SIGTERM`: stop accepting, finish what is running, exit.

## 6. Make rollback boring

If rolling back means rebuilding the previous commit, people will try to "fix
forward" under pressure instead. Keep the previous release warm on disk:

- `updatool rollback` = start the kept slot → health → switch → stop the bad one.
  Seconds, no build.
- Keep at least two releases of images (`KEEP_RELEASES`), and let `gc` clean the rest.

## 7. Protect the neighbours

On a shared host, the build competes with the app your users are using.

- Cap the builder: `BUILD_CPUS=2`, `BUILD_MEMORY=4g`.
- Prefer building off-peak for cold builds; warm builds are short enough to run anytime.

## 8. Everything machine-readable

Deploys are increasingly run by CI and by AI agents. Prose logs are for humans;
machines need contracts.

- **`--json`** on every command, one object on stdout, human progress on stderr.
- **Stable exit codes** that say *what happened to production*
  (`docs/exit-codes.md`): `3/4/5/9/75` mean "production untouched".
- An **agent skill** (`skills/updatool/SKILL.md`) that encodes these rules, so an
  agent behaves like a careful operator: look first, guard against races, never
  force a lock, roll back fast.

---

### Checklist for a new app

- [ ] `updatool init`, then `updatool doctor` is all green
- [ ] Dockerfile uses cache mounts (preset) and a non-root user
- [ ] `HEALTH_PATH` checks real readiness; app exits cleanly on `SIGTERM`
- [ ] `CHECK_CMD` runs the type check and tests
- [ ] `BUILD_CPUS` set on shared hosts
- [ ] Proxy file provider points to a **directory** (Traefik) or an imported snippet (Caddy/Nginx)
- [ ] One `updatool ship` + one `updatool rollback` rehearsed before the first real release
