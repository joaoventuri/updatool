# shellcheck shell=bash
# Two fixed slots per app — <app>-blue and <app>-green. The idle slot receives
# the new version; the old one is stopped (not removed) after the switch, so a
# rollback is just "start it again and switch back".

slot_run_args() { # slot version → prints one docker run argument per line
  local slot="$1" version="$2"
  printf '%s\n' -d --name "$(container_name "$slot")" --restart unless-stopped \
    --label "io.updatool.app=$APP" --label "io.updatool.slot=$slot" --label "io.updatool.version=$version" \
    -e "APP_VERSION=$version" -e "UPDATOOL_SLOT=$slot"
  if [ -n "$NETWORK" ]; then printf '%s\n' --network "$NETWORK"; fi
  if [ -n "$SLOT_HOST_PORTS" ]; then printf '%s\n' -p "127.0.0.1:$(slot_host_port "$slot"):$PORT"; fi
  # RUN_ARGS: shell words from the operator's config; $UPDATOOL_VERSION,
  # $UPDATOOL_SLOT and $UPDATOOL_APP are available (use single quotes in the file).
  if [ -n "$RUN_ARGS" ]; then expand_words "$RUN_ARGS" "$version" "$slot"; fi
  printf '%s\n' "$IMAGE:$version"
}

slot_host_port() { # blue → first port, green → second
  # shellcheck disable=SC2206
  local p=($SLOT_HOST_PORTS)
  if [ "$1" = blue ]; then echo "${p[0]}"; else echo "${p[1]}"; fi
}

# Where the proxy reaches a slot.
slot_upstream() {
  if [ -n "$SLOT_HOST_PORTS" ]; then echo "127.0.0.1:$(slot_host_port "$1")"
  else echo "$(container_name "$1"):$PORT"; fi
}

start_slot() { # slot version
  local slot="$1" version="$2" name args=()
  name="$(container_name "$slot")"
  docker image inspect "$IMAGE:$version" >/dev/null 2>&1 || die "image $IMAGE:$version not found (build first)" "$EXIT_BUILD"
  docker rm -f "$name" >/dev/null 2>&1 || true
  mapfile -t args < <(slot_run_args "$slot" "$version")
  step "start $name ($version)"
  docker run "${args[@]}" >/dev/null || finish "$EXIT_HEALTH" health_failed "could not start $name — production untouched" slot "$slot" version "$version"
  state_set "slot.$slot" "$version"
}

# 0 = healthy. Tries, in order: the slot's host port, wget/curl inside the
# container, and a throwaway busybox on the slot network.
probe_slot() { # slot
  local slot="$1" name url path="${HEALTH_PATH:-/}"
  name="$(container_name "$slot")"
  if [ -n "$SLOT_HOST_PORTS" ] && command -v curl >/dev/null 2>&1; then
    curl -fsS -L -o /dev/null --max-time 5 "http://127.0.0.1:$(slot_host_port "$slot")$path" && return 0
  fi
  url="http://127.0.0.1:$PORT$path"
  if docker exec "$name" sh -c "command -v wget >/dev/null 2>&1 && wget -q -T 5 -O /dev/null '$url' || curl -fsS -L -o /dev/null --max-time 5 '$url'" >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$NETWORK" ]; then
    docker run --rm --network "$NETWORK" busybox:1.36 wget -q -T 5 -O /dev/null "http://$name:$PORT$path" >/dev/null 2>&1 && return 0
  fi
  return 1
}

wait_healthy() { # slot
  local slot="$1" name deadline running
  name="$(container_name "$slot")"
  deadline=$(( $(date +%s) + HEALTH_TIMEOUT ))
  step "health: GET $HEALTH_PATH on $name (up to ${HEALTH_TIMEOUT}s)"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    running="$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)"
    if [ "$running" != true ]; then
      docker logs --tail 30 "$name" >&2 2>&1 || true
      return 1
    fi
    if probe_slot "$slot"; then ok "$name is healthy"; return 0; fi
    sleep 1
  done
  docker logs --tail 30 "$name" >&2 2>&1 || true
  return 1
}

stop_slot() { # slot — stop but keep for instant rollback
  local name; name="$(container_name "$1")"
  docker stop -t "$STOP_TIMEOUT" "$name" >/dev/null 2>&1 || true
}

slot_running() { [ "$(docker inspect -f '{{.State.Running}}' "$(container_name "$1")" 2>/dev/null || echo false)" = true ]; }

run_hook() { # name command slot version
  local name="$1" cmd="$2"
  [ -n "$cmd" ] || return 0
  step "hook $name: $cmd"
  ( cd "$CONFIG_DIR" && UPDATOOL_APP="$APP" UPDATOOL_SLOT="$3" UPDATOOL_VERSION="$4" \
      UPDATOOL_CONTAINER="$(container_name "$3")" bash -c "$cmd" ) >&2
}
