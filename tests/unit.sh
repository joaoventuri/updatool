#!/usr/bin/env bash
# Unit tests for the pure helpers (no Docker needed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export UPDATOOL_HOME="$ROOT"
# shellcheck source=../lib/core.sh
. "$ROOT/lib/core.sh"
# shellcheck source=../lib/config.sh
. "$ROOT/lib/config.sh"
# shellcheck source=../lib/lock.sh
. "$ROOT/lib/lock.sh"
# shellcheck source=../lib/state.sh
. "$ROOT/lib/state.sh"
# shellcheck source=../lib/slots.sh
. "$ROOT/lib/slots.sh"
# shellcheck source=../lib/proxy.sh
. "$ROOT/lib/proxy.sh"
# shellcheck source=../lib/commands.sh
. "$ROOT/lib/commands.sh"
usage() { :; }

FAIL=0
eq() { if [ "$2" = "$3" ]; then printf '  ✔ %s\n' "$1"; else printf '  ✖ %s\n    want: %s\n    got:  %s\n' "$1" "$3" "$2"; FAIL=1; fi; }

eq "json_str escapes quotes, backslashes and newlines" "$(json_str $'a"b\\c\nd')" '"a\"b\\c\nd"'
eq "json_obj raw values with @" "$(json_obj ok @true n @3 s x)" '{"ok":true,"n":3,"s":"x"}'

config_defaults; APP=shop; PORT=8080; NETWORK=web
eq "slot upstream on a docker network" "$(slot_upstream green)" "shop-green:8080"
SLOT_HOST_PORTS="4001 4002"
eq "slot upstream with host ports" "$(slot_upstream green)" "127.0.0.1:4002"
SLOT_HOST_PORTS=""

TRAEFIK_RULE='Host(`shop.example.com`)'; TRAEFIK_ENTRYPOINTS="web,websecure"; TRAEFIK_CERTRESOLVER=le
cfg="$(traefik_config shop-blue:8080)"
eq "traefik: service url" "$(grep -o 'http://[^"]*' <<<"$cfg")" "http://shop-blue:8080"
eq "traefik: entrypoints" "$(grep -o 'entryPoints: .*' <<<"$cfg")" "entryPoints: [web, websecure]"
eq "traefik: cert resolver" "$(grep -c 'certResolver: le' <<<"$cfg")" "1"
TRAEFIK_SERVICE_ONLY=1
eq "traefik: service-only has no router" "$(grep -c 'routers:' <<<"$(traefik_config shop-blue:8080)" || true)" "0"

# expand_words: placeholders in RUN_ARGS / BUILD_ARGS
APP=shop
eq "expand_words fills the version" "$(expand_words '-e GIT_SHA=$UPDATOOL_VERSION --label "a b"' abc1234 green | tr '\n' '|')" "-e|GIT_SHA=abc1234|--label|a b|"

# PROXY_TEMPLATE rendering keeps the user's file and swaps the target
CONFIG_DIR="$(mktemp -d)"; printf 'url: http://{{UPSTREAM}}\nslot: {{SLOT}} app: {{APP}}\n' > "$CONFIG_DIR/route.tpl"
PROXY_TEMPLATE=route.tpl; STATE_DIR="$CONFIG_DIR/state"; PORT=8080; NETWORK=web
eq "template: upstream" "$(render_template green shop-green:8080 | head -1)" "url: http://shop-green:8080"
eq "template: slot and app" "$(render_template green shop-green:8080 | tail -1)" "slot: green app: shop"
PROXY_TEMPLATE=""; rm -rf "$CONFIG_DIR"

CONFIG_DIR=/srv/app; CONTEXT=src; DOCKERFILE=Dockerfile
eq "dockerfile inside the context" "$(dockerfile_path)" "/srv/app/src/Dockerfile"
DOCKERFILE=/opt/x/Dockerfile.prod
eq "absolute dockerfile kept" "$(dockerfile_path)" "/opt/x/Dockerfile.prod"
CONTEXT=.; DOCKERFILE=Dockerfile

tmp="$(mktemp -d)"
touch "$tmp/package.json"; echo '{"dependencies":{"next":"16"}}' > "$tmp/package.json"
eq "detect Next.js" "$(detect_stack "$tmp")" "nextjs"
rm "$tmp/package.json"; touch "$tmp/go.mod"
eq "detect Go" "$(detect_stack "$tmp")" "go"
rm -rf "$tmp"

for f in "$ROOT"/presets/*.Dockerfile; do
  eq "preset $(basename "$f") uses a cache mount" "$(grep -c -- '--mount=type=cache' "$f" | awk '{print ($1>0)}')" "1"
done

[ "$FAIL" = 0 ] && echo "ALL UNIT TESTS PASSED" || { echo "UNIT TESTS FAILED"; exit 1; }
