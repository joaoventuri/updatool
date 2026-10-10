# shellcheck shell=bash
# Commands.

# ── ship ────────────────────────────────────────────────────────────────────
cmd_ship() {
  parse_opts "$@"; config_load; config_validate
  local version live idle prev_version
  version="$(release_version)"
  lock_acquire ship "$version"
  prepare_source "$version"

  live="$(live_slot)"; prev_version="$(live_version)"
  if [ -n "$OPT_EXPECT" ] && [ "$OPT_EXPECT" != "$prev_version" ]; then
    finish "$EXIT_EXPECT" expect_mismatch "live version is '${prev_version:-none}', expected '$OPT_EXPECT' — someone shipped meanwhile; nothing changed" live_version "$prev_version"
  fi
  if [ -n "$live" ] && [ "$prev_version" = "$version" ] && [ "$OPT_FORCE" != 1 ]; then
    finish "$EXIT_OK" unchanged "$version is already live (use --force to ship it again)" version "$version" slot "$live"
  fi

  say "${C_BOLD}ship${C_RESET} $APP ${prev_version:-(first ship)} → ${C_BOLD}$version${C_RESET}"
  run_checks
  BUILD_SECONDS=0
  if [ "$OPT_SKIP_BUILD" = 1 ]; then
    docker image inspect "$IMAGE:$version" >/dev/null 2>&1 || die "--skip-build but $IMAGE:$version does not exist" "$EXIT_BUILD"
  else
    build_image "$version"
  fi

  if [ -n "$live" ]; then idle="$(idle_slot)"; else idle="blue"; fi
  start_slot "$idle" "$version"
  if ! wait_healthy "$idle"; then
    stop_slot "$idle"
    history_add ship "$version" "$idle" health_failed
    finish "$EXIT_HEALTH" health_failed "$(container_name "$idle") never became healthy — production untouched (logs: docker logs $(container_name "$idle"))" version "$version" slot "$idle"
  fi

  if ! run_hook pre_switch "$HOOK_PRE_SWITCH" "$idle" "$version"; then
    stop_slot "$idle"
    history_add ship "$version" "$idle" hook_failed
    finish "$EXIT_FAIL" hook_failed "HOOK_PRE_SWITCH failed — traffic not switched, production untouched" version "$version"
  fi

  switch_traffic "$idle" "$live"

  if [ -n "$live" ] && [ "$live" != "$idle" ]; then
    step "drain ${DRAIN_SECONDS}s, then stop $(container_name "$live") (kept for rollback)"
    sleep "$DRAIN_SECONDS"
    stop_slot "$live"
  fi
  run_hook post_switch "$HOOK_POST_SWITCH" "$idle" "$version" || warn "HOOK_POST_SWITCH failed (traffic already on the new version)"
  history_add ship "$version" "$idle" ok
  prune_images >/dev/null 2>&1 || true
  finish "$EXIT_OK" shipped "shipped $version on $(container_name "$idle")" \
    version "$version" slot "$idle" previous_version "$prev_version" build_seconds "@${BUILD_SECONDS:-0}"
}

# ── rollback ────────────────────────────────────────────────────────────────
cmd_rollback() {
  parse_opts "$@"; config_load; config_validate
  lock_acquire rollback ""
  local live back back_version live_version_now name
  live="$(live_slot)"
  [ -n "$live" ] || die "nothing is live yet — nothing to roll back" "$EXIT_USAGE"
  if [ "$live" = blue ]; then back=green; else back=blue; fi
  back_version="$(slot_version "$back")"; live_version_now="$(slot_version "$live")"
  [ -n "$back_version" ] || die "no previous release in the $back slot" "$EXIT_USAGE"
  name="$(container_name "$back")"
  say "${C_BOLD}rollback${C_RESET} $APP $live_version_now → ${C_BOLD}$back_version${C_RESET}"
  if docker container inspect "$name" >/dev/null 2>&1; then
    step "start $name (kept from the previous ship)"
    docker start "$name" >/dev/null || die "could not start $name" "$EXIT_HEALTH"
  else
    start_slot "$back" "$back_version"
  fi
  wait_healthy "$back" || { stop_slot "$back"; finish "$EXIT_HEALTH" health_failed "$name did not become healthy — still on $live_version_now"; }
  switch_traffic "$back" "$live"
  step "drain ${DRAIN_SECONDS}s, then stop $(container_name "$live")"
  sleep "$DRAIN_SECONDS"
  stop_slot "$live"
  history_add rollback "$back_version" "$back" ok
  finish "$EXIT_OK" rolled_back "rolled back to $back_version on $name" version "$back_version" slot "$back" previous_version "$live_version_now"
}

# ── build / check ───────────────────────────────────────────────────────────
cmd_build() {
  parse_opts "$@"; config_load; config_validate
  local version; version="$(release_version)"
  lock_acquire build "$version"
  prepare_source "$version"
  run_checks
  build_image "$version"
  history_add build "$version" - ok
  finish "$EXIT_OK" built "built $IMAGE:$version" version "$version" build_seconds "@$BUILD_SECONDS"
}

cmd_check() {
  parse_opts "$@"; config_load
  [ -n "$CHECK_CMD" ] || finish "$EXIT_OK" no_checks "CHECK_CMD is empty — nothing to run"
  OPT_SKIP_CHECKS=0; run_checks
  finish "$EXIT_OK" checks_passed "checks passed"
}

# ── status / history / lock / logs ──────────────────────────────────────────
cmd_status() {
  parse_opts "$@"; config_load; config_validate
  local live idle holder lr ir
  live="$(live_slot)"; idle="$(idle_slot)"; holder="$(lock_holder)"
  lr=false; ir=false
  if [ -n "$live" ] && slot_running "$live"; then lr=true; fi
  if slot_running "$idle"; then ir=true; fi
  if [ "$JSON_MODE" = 1 ]; then
    json_obj app "$APP" live_slot "$live" live_version "$(live_version)" live_running "@$lr" \
      idle_slot "$idle" idle_version "$(slot_version "$idle")" idle_running "@$ir" \
      locked "@$([ -n "$holder" ] && echo true || echo false)" lock_holder "$holder" proxy "$PROXY"
    echo; return 0
  fi
  printf '%s%s%s\n' "$C_BOLD" "$APP" "$C_RESET"
  printf '  live   %-6s %s %s\n' "${live:-—}" "$(live_version)" "$([ "$lr" = true ] && echo "${C_GREEN}running${C_RESET}" || echo "${C_YELLOW}not running${C_RESET}")"
  printf '  idle   %-6s %s %s\n' "$idle" "$(slot_version "$idle")" "$([ "$ir" = true ] && echo running || echo "${C_DIM}stopped (rollback target)${C_RESET}")"
  printf '  lock   %s\n' "${holder:-free}"
  printf '  proxy  %s\n' "$PROXY"
}

cmd_history() {
  parse_opts "$@"; config_load; config_validate
  local f; f="$(app_dir)/history.tsv"
  if [ "$JSON_MODE" = 1 ]; then
    local first=1 t a v s r u secs
    printf '['
    if [ -f "$f" ]; then
      while IFS=$'\t' read -r t a v s r u secs; do
        [ $first = 1 ] || printf ','; first=0
        json_obj time "$t" action "$a" version "$v" slot "$s" result "$r" user "$u" seconds "@${secs:-0}"
      done < <(tail -n 50 "$f")
    fi
    printf ']\n'; return 0
  fi
  [ -f "$f" ] || { say "no history yet"; return 0; }
  printf '%-20s %-9s %-22s %-6s %-14s %-12s %s\n' TIME ACTION VERSION SLOT RESULT USER SECONDS
  tail -n 20 "$f" | awk -F'\t' '{printf "%-20s %-9s %-22s %-6s %-14s %-12s %s\n",$1,$2,$3,$4,$5,$6,$7}'
}

cmd_lock() {
  parse_opts "$@"; config_load; config_validate
  local holder; holder="$(lock_holder)"
  if lock_is_free; then holder=""; fi
  if [ "$JSON_MODE" = 1 ]; then json_obj locked "@$([ -n "$holder" ] && echo true || echo false)" holder "$holder"; echo; return 0; fi
  echo "${holder:-free}"
}

cmd_logs() {
  parse_opts "$@"; config_load; config_validate
  local live; live="$(live_slot)"; [ -n "$live" ] || die "nothing is live yet" "$EXIT_USAGE"
  exec docker logs -f --tail 100 "$(container_name "$live")"
}

# ── gc ──────────────────────────────────────────────────────────────────────
prune_images() {
  local keep=() tag n=0
  keep+=("$(slot_version blue)" "$(slot_version green)")
  while read -r tag; do
    [ -n "$tag" ] || continue
    n=$((n + 1))
    if [ "$n" -le "$KEEP_RELEASES" ] || printf '%s\n' "${keep[@]}" | grep -qx -- "$tag"; then continue; fi
    docker rmi "$IMAGE:$tag" >/dev/null 2>&1 || true
  done < <(docker images "$IMAGE" --format '{{.Tag}}' 2>/dev/null)
}

cmd_gc() {
  parse_opts "$@"; config_load; config_validate
  lock_acquire gc ""
  step "removing old images (keeping $KEEP_RELEASES + both slots)"
  prune_images
  step "trimming the build cache to ${GC_KEEP_STORAGE:-20gb}"
  docker buildx prune --builder "$BUILDER_NAME" --keep-storage "${GC_KEEP_STORAGE:-20gb}" -f >/dev/null 2>&1 || true
  finish "$EXIT_OK" gc_done "cleanup done"
}

# ── doctor ──────────────────────────────────────────────────────────────────
cmd_doctor() {
  parse_opts "$@"; config_load optional
  local results=() fails=0
  check_item() { # name ok? detail
    if [ "$2" = 1 ]; then ok "$1 ${C_DIM}$3${C_RESET}"; else err "$1 — $3"; fails=$((fails + 1)); fi
    results+=("$(json_obj check "$1" ok "@$([ "$2" = 1 ] && echo true || echo false)" detail "$3")")
  }
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then check_item docker 1 "$(docker version -f '{{.Server.Version}}' 2>/dev/null)"; else check_item docker 0 "docker not reachable (installed? permission?)"; fi
  if docker buildx version >/dev/null 2>&1; then check_item buildx 1 "$(docker buildx version | awk '{print $2}')"; else check_item buildx 0 "docker buildx missing"; fi
  if command -v flock >/dev/null 2>&1; then check_item flock 1 "util-linux"; else check_item flock 0 "install util-linux"; fi
  if [ -f "$CONFIG_FILE" ]; then check_item config 1 "$CONFIG_FILE"; else check_item config 0 "$CONFIG_FILE missing (updatool init)"; fi
  if [ -n "${APP:-}" ]; then
    if mkdir -p "$(app_dir)" 2>/dev/null && [ -w "$(app_dir)" ]; then check_item state 1 "$(app_dir)"; else check_item state 0 "$(app_dir) not writable"; fi
    if [ -n "$NETWORK" ]; then
      if docker network inspect "$NETWORK" >/dev/null 2>&1; then check_item network 1 "$NETWORK"; else check_item network 0 "docker network '$NETWORK' not found"; fi
    fi
    if [ -f "$(dockerfile_path)" ]; then
      if grep -q -- '--mount=type=cache' "$(dockerfile_path)"; then check_item cache 1 "Dockerfile uses RUN --mount=type=cache"
      else check_item cache 0 "Dockerfile has no cache mounts — see presets/ (builds stay slow)"; fi
    fi
    case "$PROXY" in
      traefik) if [ -d "$(dirname "$TRAEFIK_FILE")" ]; then check_item proxy 1 "traefik file provider dir $(dirname "$TRAEFIK_FILE")"; else check_item proxy 0 "$(dirname "$TRAEFIK_FILE") does not exist"; fi ;;
      caddy)   check_item proxy 1 "caddy (reload: $CADDY_RELOAD)" ;;
      nginx)   check_item proxy 1 "nginx (reload: $NGINX_RELOAD)" ;;
      none)    check_item proxy 1 "none (hooks only)" ;;
    esac
  fi
  if [ "$JSON_MODE" = 1 ]; then
    local IFS=,; printf '{"ok":%s,"checks":[%s]}\n' "$([ $fails = 0 ] && echo true || echo false)" "${results[*]}"
  fi
  [ $fails = 0 ] || exit "$EXIT_FAIL"
}

# ── init ────────────────────────────────────────────────────────────────────
detect_stack() {
  local d="$1"
  if [ -f "$d/package.json" ]; then
    if grep -q '"next"' "$d/package.json"; then echo nextjs; else echo node; fi
  elif [ -f "$d/go.mod" ]; then echo go
  elif [ -f "$d/Cargo.toml" ]; then echo rust
  elif [ -f "$d/pyproject.toml" ] || [ -f "$d/requirements.txt" ]; then echo python
  elif [ -f "$d/pom.xml" ]; then echo java-maven
  elif [ -f "$d/build.gradle" ] || [ -f "$d/build.gradle.kts" ]; then echo java-gradle
  elif [ -f "$d/Gemfile" ]; then echo ruby
  elif [ -f "$d/composer.json" ]; then echo php
  elif compgen -G "$d/*.csproj" >/dev/null || compgen -G "$d/*.sln" >/dev/null; then echo dotnet
  else echo generic; fi
}

cmd_init() {
  parse_opts "$@"
  local dir stack app
  dir="$(pwd)"; stack="$(detect_stack "$dir")"
  app="$(basename "$dir" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._\n-' '-')"
  if [ -f "$CONFIG_FILE" ] && [ "$OPT_FORCE" != 1 ]; then die "$CONFIG_FILE already exists (use --force to overwrite)" "$EXIT_USAGE"; fi
  sed -e "s/__APP__/$app/g" -e "s/__STACK__/$stack/g" "$UPDATOOL_HOME/presets/updatool.conf.example" > "$CONFIG_FILE"
  ok "wrote $CONFIG_FILE (stack: $stack)"
  if [ ! -f Dockerfile ] && [ -f "$UPDATOOL_HOME/presets/$stack.Dockerfile" ]; then
    cp "$UPDATOOL_HOME/presets/$stack.Dockerfile" Dockerfile
    ok "wrote a cache-ready Dockerfile (presets/$stack.Dockerfile)"
    if [ "$stack" = nextjs ] && [ ! -f scripts/build-next.sh ]; then
      mkdir -p scripts && cp "$UPDATOOL_HOME/presets/nextjs-build.sh" scripts/build-next.sh
      ok "wrote scripts/build-next.sh (Turbopack cache with a fresh-CSS proof)"
    fi
  elif [ -f Dockerfile ]; then
    if grep -q -- '--mount=type=cache' Dockerfile; then ok "Dockerfile already uses cache mounts"
    else warn "your Dockerfile has no cache mounts — compare with $UPDATOOL_HOME/presets/$stack.Dockerfile"; fi
  fi
  say ""
  say "Next: edit $CONFIG_FILE (proxy, network, health path), then run ${C_BOLD}updatool doctor${C_RESET} and ${C_BOLD}updatool ship${C_RESET}."
}
