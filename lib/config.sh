# shellcheck shell=bash
# Configuration: updatool.conf is a plain KEY=value file (shell syntax).
# Every key can also come from the environment (UPDATOOL_<KEY> wins).

CONFIG_KEYS=(APP IMAGE CONTEXT DOCKERFILE BUILD_ARGS BUILD_CPUS BUILD_MEMORY BUILD_PLATFORM
  CHECK_CMD PORT HEALTH_PATH HEALTH_TIMEOUT NETWORK RUN_ARGS SLOT_HOST_PORTS
  PROXY TRAEFIK_FILE TRAEFIK_RULE TRAEFIK_ENTRYPOINTS TRAEFIK_CERTRESOLVER TRAEFIK_SERVICE_ONLY
  CADDY_FILE CADDY_RELOAD NGINX_FILE NGINX_RELOAD PROXY_TEMPLATE SWITCH_SETTLE VERIFY_URL
  DRAIN_SECONDS STOP_TIMEOUT KEEP_RELEASES HOOK_PRE_SWITCH HOOK_POST_SWITCH
  STATE_DIR LOCK_WAIT)

config_defaults() {
  CONTEXT="."; DOCKERFILE="Dockerfile"; BUILD_ARGS=""; BUILD_CPUS=""; BUILD_MEMORY=""; BUILD_PLATFORM=""
  CHECK_CMD=""; PORT="3000"; HEALTH_PATH="/"; HEALTH_TIMEOUT="90"; NETWORK=""; RUN_ARGS=""
  SLOT_HOST_PORTS=""; PROXY="traefik"
  TRAEFIK_FILE=""; TRAEFIK_RULE=""; TRAEFIK_ENTRYPOINTS="web"; TRAEFIK_CERTRESOLVER=""; TRAEFIK_SERVICE_ONLY="0"
  CADDY_FILE=""; CADDY_RELOAD=""; NGINX_FILE=""; NGINX_RELOAD=""; PROXY_TEMPLATE=""
  SWITCH_SETTLE="3"; VERIFY_URL=""; DRAIN_SECONDS="5"; STOP_TIMEOUT="20"; KEEP_RELEASES="3"
  HOOK_PRE_SWITCH=""; HOOK_POST_SWITCH=""; STATE_DIR="/var/lib/updatool"; LOCK_WAIT="900"
  APP=""; IMAGE=""
}

config_load() {
  config_defaults
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  elif [ "${1:-}" != "optional" ]; then
    die "config not found: $CONFIG_FILE (run 'updatool init')" "$EXIT_USAGE"
  fi
  local k env
  for k in "${CONFIG_KEYS[@]}"; do
    env="UPDATOOL_$k"
    if [ -n "${!env:-}" ]; then printf -v "$k" '%s' "${!env}"; fi
  done
  IMAGE="${IMAGE:-$APP}"
  CONFIG_DIR="$(cd "$(dirname "$CONFIG_FILE")" 2>/dev/null && pwd || pwd)"
}

config_validate() {
  [ -n "$APP" ] || die "APP is required in $CONFIG_FILE" "$EXIT_USAGE"
  [[ $APP =~ ^[a-z0-9][a-z0-9_.-]*$ ]] || die "APP must be lowercase letters, digits, '.', '_' or '-'" "$EXIT_USAGE"
  [[ $PORT =~ ^[0-9]+$ ]] || die "PORT must be a number" "$EXIT_USAGE"
  case "$PROXY" in
    traefik) [ -n "$TRAEFIK_FILE" ] || die "PROXY=traefik needs TRAEFIK_FILE" "$EXIT_USAGE"
             [ "$TRAEFIK_SERVICE_ONLY" = 1 ] || [ -n "$TRAEFIK_RULE" ] || [ -n "$PROXY_TEMPLATE" ] || die "PROXY=traefik needs TRAEFIK_RULE, TRAEFIK_SERVICE_ONLY=1 or PROXY_TEMPLATE" "$EXIT_USAGE" ;;
    caddy)   [ -n "$CADDY_FILE" ] && [ -n "$CADDY_RELOAD" ] || die "PROXY=caddy needs CADDY_FILE and CADDY_RELOAD" "$EXIT_USAGE" ;;
    nginx)   [ -n "$NGINX_FILE" ] && [ -n "$NGINX_RELOAD" ] || die "PROXY=nginx needs NGINX_FILE and NGINX_RELOAD" "$EXIT_USAGE" ;;
    none)    : ;;
    *) die "PROXY must be traefik, caddy, nginx or none" "$EXIT_USAGE" ;;
  esac
  if [ -n "$PROXY_TEMPLATE" ] && [ ! -f "$(abs_path "$PROXY_TEMPLATE")" ]; then
    die "PROXY_TEMPLATE not found: $PROXY_TEMPLATE" "$EXIT_USAGE"
  fi
  if [ -n "$SLOT_HOST_PORTS" ]; then
    # shellcheck disable=SC2086
    set -- $SLOT_HOST_PORTS
    [ $# = 2 ] || die "SLOT_HOST_PORTS needs two ports, e.g. \"3001 3002\"" "$EXIT_USAGE"
  elif [ "$PROXY" != none ] && [ -z "$NETWORK" ]; then
    die "set NETWORK (proxy and slots on the same docker network) or SLOT_HOST_PORTS" "$EXIT_USAGE"
  fi
}

# Paths in the config are relative to the config file's directory.
abs_path() { case "$1" in /*) echo "$1" ;; *) echo "$CONFIG_DIR/$1" ;; esac; }

# The Dockerfile lives in the build context unless given as an absolute path
# (same rule as `docker build` without -f).
dockerfile_path() { case "$DOCKERFILE" in /*) echo "$DOCKERFILE" ;; *) echo "$(abs_path "$CONTEXT")/$DOCKERFILE" ;; esac; }

# Expand $UPDATOOL_* placeholders inside RUN_ARGS / BUILD_ARGS (shell words).
# The config is the operator's own file, so eval is acceptable here.
expand_words() { # string version slot → one word per line
  local UPDATOOL_APP="$APP" UPDATOOL_VERSION="$2" UPDATOOL_SLOT="${3:-}" UPDATOOL_BUILT_AT
  UPDATOOL_BUILT_AT="$(date -u +%FT%TZ)"
  local words=()
  eval "words=($1)"
  if [ ${#words[@]} -gt 0 ]; then printf '%s\n' "${words[@]}"; fi
}

# Release version: --version, else git short SHA (+ "-dirty"), else timestamp.
release_version() {
  if [ -n "$OPT_VERSION" ]; then echo "$OPT_VERSION"; return; fi
  if git -C "$CONFIG_DIR" rev-parse --short=7 HEAD >/dev/null 2>&1; then
    local v; v="$(git -C "$CONFIG_DIR" rev-parse --short=7 HEAD)"
    if [ -n "$(git -C "$CONFIG_DIR" status --porcelain 2>/dev/null)" ]; then v="$v-dirty-$(date +%H%M%S)"; fi
    echo "$v"; return
  fi
  date -u +%Y%m%d%H%M%S
}
