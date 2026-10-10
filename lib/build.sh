# shellcheck shell=bash
# Build with a PERSISTENT BuildKit builder: layer cache and RUN --mount=type=cache
# directories survive between builds, so a one-line change rebuilds in seconds.
# BUILD_CPUS / BUILD_MEMORY cap the builder so a deploy on a shared host does
# not starve the app that is serving users.

BUILDER_NAME="updatool"

builder_opts() {
  local o=()
  if [ -n "$BUILD_CPUS" ]; then
    local quota; quota=$(awk -v c="$BUILD_CPUS" 'BEGIN{printf "%d", c*100000}')
    o+=(--driver-opt "cpu-period=100000" --driver-opt "cpu-quota=$quota")
  fi
  if [ -n "$BUILD_MEMORY" ]; then o+=(--driver-opt "memory=$BUILD_MEMORY"); fi
  if [ ${#o[@]} -gt 0 ]; then printf '%s\n' "${o[@]}"; fi
}

ensure_builder() {
  need docker
  docker buildx version >/dev/null 2>&1 || die "docker buildx is required (Docker 23+)" "$EXIT_USAGE"
  local want have opts=()
  mapfile -t opts < <(builder_opts)
  want="${opts[*]:-default}"
  have="$(state_get builder.opts)"
  if docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    if [ "$want" = "$have" ]; then return 0; fi
    warn "builder limits changed ($have → $want): recreating builder (cache starts cold once)"
    docker buildx rm "$BUILDER_NAME" >/dev/null 2>&1 || true
  fi
  step "creating persistent builder '$BUILDER_NAME' ${opts[*]:+(${opts[*]})}"
  docker buildx create --name "$BUILDER_NAME" --driver docker-container "${opts[@]}" >/dev/null \
    || die "could not create the buildx builder" "$EXIT_BUILD"
  state_set builder.opts "$want"
}

# --source: each release builds from its own private copy, made only after the
# lock is held. Two agents shipping at once never overwrite each other's files
# (the classic mistake: extract into a shared ./src, then wait for the lock —
# the build that wins the lock may send the OTHER agent's files, or a mix).
SOURCE_DIR=""
prepare_source() { # version
  [ -n "$OPT_SOURCE" ] || return 0
  local dir; dir="$(app_dir)/src/$1.$$"
  rm -rf "$dir"; mkdir -p "$dir" || die "cannot create $dir" "$EXIT_USAGE"
  if [ -d "$OPT_SOURCE" ]; then
    cp -a "$OPT_SOURCE/." "$dir/" || die "could not copy $OPT_SOURCE" "$EXIT_BUILD"
  elif [ -f "$OPT_SOURCE" ]; then
    tar -xzf "$OPT_SOURCE" -C "$dir" || die "could not extract $OPT_SOURCE (expected a .tar.gz)" "$EXIT_BUILD"
  else
    die "--source not found: $OPT_SOURCE" "$EXIT_USAGE"
  fi
  SOURCE_DIR="$dir"; CONTEXT="$dir"
  step "source: $OPT_SOURCE → private snapshot"
}
cleanup_source() { if [ -n "$SOURCE_DIR" ]; then rm -rf "$SOURCE_DIR"; fi; }

run_checks() {
  if [ -z "$CHECK_CMD" ]; then return 0; fi
  if [ "$OPT_SKIP_CHECKS" = 1 ]; then warn "skipping checks (--skip-checks)"; return 0; fi
  step "checks: $CHECK_CMD"
  local log; log="$(app_dir)/last-check.log"; mkdir -p "$(app_dir)"
  if ! ( cd "${SOURCE_DIR:-$CONFIG_DIR}" && bash -c "$CHECK_CMD" ) >"$log" 2>&1; then
    tail -n 30 "$log" >&2 || true
    finish "$EXIT_CHECKS" checks_failed "checks failed — nothing was built or changed" log "$log"
  fi
  ok "checks passed"
}

build_image() { # version
  local version="$1" log args=() a
  ensure_builder
  log="$(app_dir)/last-build.log"
  while IFS= read -r a; do [ -n "$a" ] && args+=(--build-arg "$a"); done < <(expand_words "$BUILD_ARGS" "$version")
  if [ -n "$BUILD_PLATFORM" ]; then args+=(--platform "$BUILD_PLATFORM"); fi
  step "build $IMAGE:$version ${C_DIM}(log: $log)${C_RESET}"
  local t0; t0=$(date +%s)
  if ! ( cd "$CONFIG_DIR" && docker buildx build --builder "$BUILDER_NAME" \
        --provenance=false --sbom=false "${args[@]}" \
        --build-arg "APP_VERSION=$version" \
        --label "io.updatool.app=$APP" --label "io.updatool.version=$version" \
        -f "$(dockerfile_path)" -t "$IMAGE:$version" --load "$(abs_path "$CONTEXT")" ) >"$log" 2>&1; then
    tail -n 40 "$log" >&2 || true
    finish "$EXIT_BUILD" build_failed "build failed — production untouched" log "$log" version "$version"
  fi
  BUILD_SECONDS=$(( $(date +%s) - t0 ))
  ok "built $IMAGE:$version in ${BUILD_SECONDS}s"
}
