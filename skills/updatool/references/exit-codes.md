# Exit codes

Stable contract for CI and AI agents. With `--json`, the same information is in
`{"ok", "status", "exit_code", "message", …}` on stdout.

| Code | `status` | What happened to production | What to do |
|---|---|---|---|
| `0` | `shipped` · `rolled_back` · `built` · `unchanged` | Changed as requested (or nothing to do) | Verify the app |
| `1` | `error` · `hook_failed` | Depends on `message`; `hook_failed` = untouched | Read `message` |
| `2` | `error` | Untouched — bad command line or config | Fix `updatool.conf` (`updatool doctor`) |
| `3` | `checks_failed` | **Untouched** — nothing was built | Fix tests/type errors (`log` in JSON) |
| `4` | `build_failed` | **Untouched** | Read the build `log` |
| `5` | `health_failed` | **Untouched** — the new slot never got traffic | `docker logs <app>-<slot>`; fix and ship again |
| `6` | `switch_failed` | **Previous slot restored** automatically | Check the proxy route / `VERIFY_URL` |
| `9` | `expect_mismatch` | **Untouched** — someone else shipped meanwhile | Pull/rebase, review, ship again with the new `--expect` |
| `75` | `locked` | **Untouched** — another ship holds the lock | Wait (default) or report `holder`; never force |
