# shellcheck shell=bash
# Core helpers: output, JSON, exit codes, option parsing.

# ── Exit codes (stable contract for CI and AI agents; see docs/exit-codes.md)
EXIT_OK=0
EXIT_FAIL=1          # generic failure
EXIT_USAGE=2         # bad command line or config
EXIT_CHECKS=3        # CHECK_CMD failed — nothing was built or changed
EXIT_BUILD=4         # build failed — production untouched
EXIT_HEALTH=5        # new slot never became healthy — production untouched
EXIT_SWITCH=6        # switching traffic failed — previous slot restored
EXIT_EXPECT=9        # --expect did not match the live version — nothing changed
EXIT_LOCKED=75       # another ship holds the lock (EX_TEMPFAIL) — try later
export EXIT_OK EXIT_FAIL EXIT_USAGE EXIT_CHECKS EXIT_BUILD EXIT_HEALTH EXIT_SWITCH EXIT_EXPECT EXIT_LOCKED

# ── Colors only on a real terminal and never in JSON mode
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_BLUE=$'\033[34m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_GREEN=''; C_BLUE=''; C_YELLOW=''; C_RED=''
fi

JSON_MODE=0
T_START=$(date +%s)

# Human output goes to stderr so stdout stays clean for --json.
say()  { [ "$JSON_MODE" = 1 ] && return 0; printf '%s\n' "$*" >&2; }
step() { [ "$JSON_MODE" = 1 ] && return 0; printf '%s▸%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
ok()   { [ "$JSON_MODE" = 1 ] && return 0; printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s✖%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

elapsed() { echo $(( $(date +%s) - T_START )); }

# JSON string escaping (no jq dependency).
json_str() {
  local s="${1-}"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

# json_obj key value [key value ...] — values starting with @ are raw JSON.
json_obj() {
  local out="{" first=1 k v
  while [ $# -gt 1 ]; do
    k="$1"; v="$2"; shift 2
    [ $first = 1 ] || out+=","
    first=0
    if [[ $v == @* ]]; then out+="$(json_str "$k"):${v#@}"
    else out+="$(json_str "$k"):$(json_str "$v")"; fi
  done
  printf '%s}' "$out"
}

# Final result: JSON on stdout in --json mode, a short line otherwise.
# finish <exit_code> <status> <message> [extra key value ...]
finish() {
  local code="$1" status="$2" msg="$3"; shift 3
  if [ "$JSON_MODE" = 1 ]; then
    json_obj ok "@$([ "$code" = 0 ] && echo true || echo false)" status "$status" \
      exit_code "@$code" message "$msg" app "${APP:-}" seconds "@$(elapsed)" "$@"
    echo
  else
    if [ "$code" = 0 ]; then ok "$msg ${C_DIM}($(elapsed)s)${C_RESET}"; else err "$msg"; fi
  fi
  exit "$code"
}

die() { finish "${2:-$EXIT_FAIL}" error "$1"; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1" "$EXIT_USAGE"; }

# Shared option parser. Sets: CONFIG_FILE OPT_VERSION OPT_EXPECT OPT_SKIP_CHECKS
# OPT_SKIP_BUILD OPT_NO_WAIT JSON_MODE OPT_FORCE OPT_REST (remaining args).
CONFIG_FILE="${UPDATOOL_CONFIG:-./updatool.conf}"
OPT_VERSION=""; OPT_EXPECT=""; OPT_SKIP_CHECKS=0; OPT_SKIP_BUILD=0; OPT_NO_WAIT=0; OPT_FORCE=0
OPT_REST=()
parse_opts() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|--config) CONFIG_FILE="${2:?--config needs a file}"; shift ;;
      -v|--version) OPT_VERSION="${2:?--version needs a value}"; shift ;;
      --expect) OPT_EXPECT="${2:?--expect needs a version}"; shift ;;
      --skip-checks) OPT_SKIP_CHECKS=1 ;;
      --skip-build) OPT_SKIP_BUILD=1 ;;
      --no-wait) OPT_NO_WAIT=1 ;;
      --json) JSON_MODE=1 ;;
      --force) OPT_FORCE=1 ;;
      -h|--help) usage; exit 0 ;;
      *) OPT_REST+=("$1") ;;
    esac
    shift
  done
}
