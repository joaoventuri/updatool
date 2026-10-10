# shellcheck shell=bash
# Traffic switch. One atomic write (temp file + rename in the same directory),
# then the proxy's own graceful reload. Adapters: traefik, caddy, nginx, none.
#
# Traefik: point the FILE PROVIDER at a directory (bind-mount the directory, not
# the single file — a rename changes the inode and a single-file mount would
# keep serving the old one).

atomic_write() { # path content
  local path="$1" dir tmp
  dir="$(dirname "$path")"
  mkdir -p "$dir" || return 1
  tmp="$dir/.$(basename "$path").updatool.tmp"
  printf '%s\n' "$2" > "$tmp" && mv -f "$tmp" "$path"
}

traefik_config() { # upstream
  local up="$1" ep tls=""
  ep="$(printf '%s' "$TRAEFIK_ENTRYPOINTS" | tr ', ' '\n\n' | sed '/^$/d' | paste -sd, - | sed 's/,/, /g')"
  if [ -n "$TRAEFIK_CERTRESOLVER" ]; then tls=$'\n      tls:\n        certResolver: '"$TRAEFIK_CERTRESOLVER"; fi
  if [ "$TRAEFIK_SERVICE_ONLY" = 1 ]; then
    cat <<YAML
# Managed by updatool — do not edit by hand (live slot: $up).
http:
  services:
    $APP:
      loadBalancer:
        servers:
          - url: "http://$up"
YAML
  else
    cat <<YAML
# Managed by updatool — do not edit by hand (live slot: $up).
http:
  routers:
    $APP:
      rule: "$(printf '%s' "$TRAEFIK_RULE" | sed 's/"/\\"/g')"
      entryPoints: [$ep]
      service: $APP$tls
  services:
    $APP:
      loadBalancer:
        servers:
          - url: "http://$up"
YAML
  fi
}

proxy_point_to() { # slot
  local up; up="$(slot_upstream "$1")"
  case "$PROXY" in
    traefik) atomic_write "$TRAEFIK_FILE" "$(traefik_config "$up")" ;;
    caddy)   atomic_write "$CADDY_FILE" "# Managed by updatool (live slot: $1)
reverse_proxy $up" && ( bash -c "$CADDY_RELOAD" ) >&2 ;;
    nginx)   atomic_write "$NGINX_FILE" "# Managed by updatool (live slot: $1)
upstream $APP { server $up; keepalive 16; }" && ( bash -c "$NGINX_RELOAD" ) >&2 ;;
    none)    : ;;
  esac
}

verify_public() {
  [ -n "$VERIFY_URL" ] || return 0
  need curl
  local _
  for _ in $(seq 1 15); do
    if curl -fsS -L -o /dev/null --max-time 5 "$VERIFY_URL"; then return 0; fi
    sleep 1
  done
  return 1
}

# Switch traffic to <slot>. On failure, point back to <previous> and exit 6.
switch_traffic() { # slot previous_slot
  local slot="$1" prev="${2:-}"
  step "switch traffic → $(container_name "$slot")"
  if ! proxy_point_to "$slot"; then
    if [ -n "$prev" ]; then proxy_point_to "$prev" || true; fi
    finish "$EXIT_SWITCH" switch_failed "could not update the $PROXY route — previous slot kept" slot "$slot"
  fi
  sleep "$SWITCH_SETTLE"
  if ! verify_public; then
    warn "VERIFY_URL failed after the switch — switching back"
    if [ -n "$prev" ]; then proxy_point_to "$prev" || true; fi
    finish "$EXIT_SWITCH" switch_failed "public check failed on $VERIFY_URL — previous slot restored" slot "$slot"
  fi
  state_set live "$slot"
  ok "traffic is on $(container_name "$slot")"
}
