# shellcheck shell=bash
# One ship at a time per app. flock is released by the kernel when the process
# dies, so a crashed deploy never leaves a stale lock behind.

LOCK_HELD=0

app_dir() { echo "$STATE_DIR/$APP"; }

# Prints "user@host pid=… action=… version=… since=…" of the current holder, if any.
lock_holder() {
  local info; info="$(app_dir)/deploy.lock.info"
  if [ -f "$info" ]; then cat "$info"; fi
}

lock_is_free() {
  local f; f="$(app_dir)/deploy.lock"
  [ -e "$f" ] || return 0
  ( flock -n 9 ) 9>>"$f"
}

lock_acquire() {
  local action="$1" version="${2:-}" dir f
  need flock
  dir="$(app_dir)"; mkdir -p "$dir" || die "cannot create $dir (run with sudo or set STATE_DIR)" "$EXIT_USAGE"
  f="$dir/deploy.lock"
  exec 9>>"$f"
  if ! flock -n 9; then
    local holder; holder="$(lock_holder)"
    if [ "$OPT_NO_WAIT" = 1 ]; then
      finish "$EXIT_LOCKED" locked "another ship holds the lock: ${holder:-unknown}" holder "$holder"
    fi
    step "waiting for the deploy lock (held by ${holder:-unknown}, up to ${LOCK_WAIT}s)…"
    flock -w "$LOCK_WAIT" 9 || finish "$EXIT_LOCKED" locked "gave up after ${LOCK_WAIT}s waiting for: ${holder:-unknown}" holder "$holder"
  fi
  LOCK_HELD=1
  printf '%s@%s pid=%s action=%s version=%s since=%s\n' \
    "${SUDO_USER:-${USER:-$(id -un)}}" "$(hostname)" "$$" "$action" "$version" "$(date -u +%FT%TZ)" > "$dir/deploy.lock.info"
  trap lock_release EXIT
}

lock_release() {
  [ "$LOCK_HELD" = 1 ] || return 0
  rm -f "$(app_dir)/deploy.lock.info"
  flock -u 9 2>/dev/null || true
  LOCK_HELD=0
}
