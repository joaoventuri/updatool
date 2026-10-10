#!/usr/bin/env bash
# End-to-end test: real Docker, real Traefik, real traffic.
#   ship v1 → v2 → v3 → rollback under continuous load  ⇒  zero failed requests
#   plus: lock contention (exit 75), --expect guard (exit 9), bad health (exit 5).
# Everything it creates is prefixed "ut-e2e" and removed at the end.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UT="$ROOT/bin/updatool"
WORK="$(mktemp -d)"
NET=ut-e2e-net
PORT_PUB=18080
FAIL=0

cleanup() {
  docker rm -f ut-e2e-traefik ut-e2e-blue ut-e2e-green >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  [ -n "${LOAD_PID:-}" ] && kill "$LOAD_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✖\033[0m %s\n' "$*"; FAIL=1; }

echo "▸ setup ($WORK)"
docker network create "$NET" >/dev/null
mkdir -p "$WORK/dyn" "$WORK/state"
cp -r "$ROOT/examples/node-hello" "$WORK/app"
docker run -d --name ut-e2e-traefik --network "$NET" -p "127.0.0.1:$PORT_PUB:80" \
  -v "$WORK/dyn:/dyn:ro" traefik:v3.4 \
  --entrypoints.web.address=:80 --providers.file.directory=/dyn --providers.file.watch=true >/dev/null

cat > "$WORK/app/updatool.conf" <<EOF
APP=ut-e2e
PORT=3000
HEALTH_PATH=/health
HEALTH_TIMEOUT=60
NETWORK=$NET
RUN_ARGS="-e RESPONSE_DELAY_MS=120"
PROXY=traefik
TRAEFIK_FILE=$WORK/dyn/ut-e2e.yml
TRAEFIK_RULE='PathPrefix(\`/\`)'
TRAEFIK_ENTRYPOINTS=web
SWITCH_SETTLE=2
DRAIN_SECONDS=3
STOP_TIMEOUT=15
STATE_DIR=$WORK/state
EOF

served() { curl -fsS --max-time 5 "http://127.0.0.1:$PORT_PUB/" 2>/dev/null | tr -d '\n'; }
ut() { (cd "$WORK/app" && "$UT" "$@"); }

echo "▸ first ship (v1)"
ut ship --version v1 --json > "$WORK/out1.json"
sleep 2
[ "$(served)" = v1 ] && pass "v1 is live" || fail "v1 not served (got '$(served)')"

echo "▸ continuous load starts (8 parallel clients)"
: > "$WORK/codes.txt"
(
  while :; do
    for _ in 1 2 3 4 5 6 7 8; do
      ( curl -s -o /dev/null -m 10 -w '%{http_code}\n' "http://127.0.0.1:$PORT_PUB/" >> "$WORK/codes.txt" ) &
    done
    wait
  done
) &
LOAD_PID=$!
sleep 2

for v in v2 v3; do
  echo "▸ ship $v under load"
  ut ship --version "$v" --json > "$WORK/out-$v.json" || fail "ship $v exited $?"
  [ "$(served)" = "$v" ] && pass "$v is live" || fail "$v not served (got '$(served)')"
done

echo "▸ rollback under load"
ut rollback --json > "$WORK/out-rb.json" || fail "rollback exited $?"
[ "$(served)" = v2 ] && pass "rolled back to v2" || fail "rollback did not serve v2 (got '$(served)')"

sleep 2
kill "$LOAD_PID" 2>/dev/null || true; wait "$LOAD_PID" 2>/dev/null || true; LOAD_PID=""
total=$(wc -l < "$WORK/codes.txt"); bad=$(grep -vc '^200$' "$WORK/codes.txt" || true)
if [ "$bad" = 0 ] && [ "$total" -gt 100 ]; then pass "zero downtime: $total requests, 0 failures"
else fail "downtime detected: $bad of $total requests failed"; sort "$WORK/codes.txt" | uniq -c; fi

echo "▸ --expect guard"
set +e; ut ship --version v9 --expect v1 --json > "$WORK/out-exp.json"; code=$?; set -e
[ "$code" = 9 ] && pass "--expect mismatch → exit 9, nothing changed" || fail "--expect returned $code"
[ "$(served)" = v2 ] || fail "--expect changed traffic"

echo "▸ lock contention"
mkdir -p "$WORK/state/ut-e2e"
( flock 9; echo "tester@ci pid=1 action=ship version=vX since=now" > "$WORK/state/ut-e2e/deploy.lock.info"; sleep 8 ) 9>>"$WORK/state/ut-e2e/deploy.lock" &
HOLD=$!; sleep 1
set +e; ut ship --version v8 --no-wait --json > "$WORK/out-lock.json"; code=$?; set -e
[ "$code" = 75 ] && pass "busy lock → exit 75 with holder: $(grep -o 'tester@ci[^"]*' "$WORK/out-lock.json" | head -1)" || fail "lock returned $code"
wait "$HOLD" 2>/dev/null || true

echo "▸ unhealthy release never gets traffic"
sed -i 's#^HEALTH_PATH=.*#HEALTH_PATH=/does-not-exist-404#; s#^HEALTH_TIMEOUT=.*#HEALTH_TIMEOUT=8#' "$WORK/app/updatool.conf"
sed -i 's#if (req.url === "/health")#if (req.url === "/never")#; s#res.writeHead(200, { "content-type"#res.writeHead(req.url === "/" ? 200 : 404, { "content-type"#' "$WORK/app/server.js"
set +e; ut ship --version v-bad --json > "$WORK/out-bad.json"; code=$?; set -e
[ "$code" = 5 ] && pass "bad release → exit 5" || fail "bad release returned $code"
[ "$(served)" = v2 ] && pass "traffic stayed on v2" || fail "traffic moved to a bad release (got '$(served)')"

echo "▸ status --json"
ut status --json | grep -q '"live_version":"v2"' && pass "status reports v2 live" || fail "status mismatch: $(ut status --json)"

echo
if [ "$FAIL" = 0 ]; then echo "ALL E2E CHECKS PASSED"; else echo "E2E FAILED"; exit 1; fi
