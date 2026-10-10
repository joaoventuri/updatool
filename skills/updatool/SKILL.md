---
name: updatool
description: Build, ship and roll back containerized apps in production with zero downtime using updatool (blue/green slots, incremental build cache, deploy lock, JSON contract). Use when the user asks to deploy, publish, release, ship, "put in production", swap versions, roll back, speed up a slow Docker build, or set up zero-downtime deploys on a VPS/server — for any language. Also use before any action that changes a running production app, to check who else is deploying.
license: MIT
compatibility: Requires bash 4.4+, Docker with buildx, flock (util-linux) and SSH or shell access to the server. Network access for image pulls.
---

# updatool — deploy like a careful senior engineer

updatool ships containers with blue/green slots. Production changes in exactly
one step (the route switch), only after the new slot is healthy, and the
previous slot is kept for an instant rollback. Your job is to drive it safely.

## Golden rules

1. **Ask before changing production** unless the user already authorized this
   specific deploy. Building, `status`, `doctor` and `history` are always safe.
2. **Look first**: run `updatool status --json` and note `live_version` and `locked`.
3. **Guard the race**: always ship with `--expect <live_version you saw>`.
4. **Never break a lock.** Exit `75` means someone else is shipping: wait, or
   tell the user who holds it (`holder`). Do not delete lock files or kill processes.
5. **Never skip the gate** (`--skip-checks`) unless the user explicitly asks.
6. **Always use `--json`** and decide from `exit_code`/`status`, not from prose.
7. **After a ship, verify** the app (the URL or endpoint the user cares about).
   If it misbehaves, `updatool rollback --json` first, investigate after.

## Ship

```bash
updatool status --json                      # → {"live_version":"a1b2c3d","locked":false,...}
updatool ship --expect a1b2c3d --json       # check → build → idle slot → health → switch → drain
```

Read the result:

| exit | meaning | your next step |
|---|---|---|
| 0 | shipped (or `unchanged`) | verify, report version + seconds |
| 3 | checks failed — nothing built | show the failing part of `log`, fix, retry |
| 4 | build failed — production untouched | read `log`, fix, retry |
| 5 | new slot unhealthy — production untouched | `docker logs <app>-<slot>`, fix, retry |
| 6 | switch failed — previous slot restored | inspect proxy route / `VERIFY_URL` |
| 9 | someone shipped meanwhile — nothing changed | pull/rebase, review their change, ship with the new `--expect` |
| 75 | locked — nothing changed | wait (default waits `LOCK_WAIT`) or report `holder` |

Full table: [references/exit-codes.md](references/exit-codes.md).

## Roll back

```bash
updatool rollback --json   # starts the kept slot, health, switch, stops the bad one — seconds
```

Only one step back is instant (the other slot). For older releases, ship that
commit/version again: `updatool ship --version <old> --skip-build` if its image
still exists (`docker images <app>`), otherwise check it out and ship normally.

## Set up a new app

```bash
updatool init      # detects stack, writes updatool.conf (+ cache-ready Dockerfile)
updatool doctor    # must be all green before the first ship
```

Then, with the user: set `PORT`, a real `HEALTH_PATH`, `NETWORK` (shared with
the proxy), the proxy block, `RUN_ARGS` (env file, volumes) and `CHECK_CMD`.
Rehearse once: `updatool ship`, then `updatool rollback`. Details:
[references/setup.md](references/setup.md).

## Make builds fast

If builds are slow, check in this order:

1. `updatool doctor` → "Dockerfile has no cache mounts"? Copy the right preset
   from `presets/<stack>.Dockerfile` (cache mounts for the package manager and
   the compiler/framework cache).
2. Type checks/tests inside the Dockerfile? Move them to `CHECK_CMD`.
3. Lockfile copied after the source? Copy it first so installs stay cached.
4. Huge build context? Add a `.dockerignore` (`.git`, `node_modules`, build output).
5. Shared host? Set `BUILD_CPUS` so the build does not slow the live app.

## Multiple agents / people on the same app

The lock already serializes ships. Additionally:

- Before you start long work, run `updatool lock --json`; if busy, coordinate.
- Ship what is on the main branch: rebase on the latest main so your build
  contains everyone's merged work; `--expect` catches the rest.
- Never deploy someone else's unfinished branch to unblock yourself.

## Reporting to the user

Keep it short and factual: version shipped, slot, total seconds (build seconds
if relevant), what you verified, and how to roll back (`updatool rollback`).
If production was untouched because of a failure, say so explicitly.
