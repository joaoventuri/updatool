# shellcheck shell=bash
# State lives in $STATE_DIR/$APP:
#   live            → name of the slot receiving traffic ("blue" | "green")
#   slot.blue       → version running (or kept) in the blue slot
#   slot.green      → version running (or kept) in the green slot
#   history.tsv     → time, action, version, slot, result, user, seconds

state_get() { local f; f="$(app_dir)/$1"; if [ -f "$f" ]; then cat "$f"; fi; }
state_set() { local d; d="$(app_dir)"; mkdir -p "$d"; printf '%s\n' "$2" > "$d/.$1.tmp" && mv "$d/.$1.tmp" "$d/$1"; }

live_slot()   { state_get live; }
idle_slot()   { if [ "$(live_slot)" = blue ]; then echo green; else echo blue; fi; }
slot_version(){ state_get "slot.$1"; }
live_version(){ local s; s="$(live_slot)"; if [ -n "$s" ]; then slot_version "$s"; fi; }

history_add() { # action version slot result
  local d; d="$(app_dir)"; mkdir -p "$d"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$4" \
    "${SUDO_USER:-${USER:-$(id -un)}}" "$(elapsed)" >> "$d/history.tsv"
}

container_name() { echo "$APP-$1"; }   # myapp-blue / myapp-green
