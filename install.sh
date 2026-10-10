#!/usr/bin/env sh
# updatool installer
#   curl -fsSL https://raw.githubusercontent.com/joaoventuri/updatool/main/install.sh | sh
# Env: UPDATOOL_REF (branch or tag, default main) · PREFIX (default /usr/local)
set -eu
REF="${UPDATOOL_REF:-main}"
PREFIX="${PREFIX:-/usr/local}"
DEST="$PREFIX/lib/updatool"
URL="https://github.com/joaoventuri/updatool/archive/refs/heads/$REF.tar.gz"
case "$REF" in v[0-9]*) URL="https://github.com/joaoventuri/updatool/archive/refs/tags/$REF.tar.gz" ;; esac

# sudo only when the closest existing directory is not writable by us
SUDO=""
probe="$PREFIX/lib"; [ -d "$probe" ] || probe="$PREFIX"; [ -d "$probe" ] || probe="$(dirname "$PREFIX")"
if [ "$(id -u)" != 0 ] && [ ! -w "$probe" ]; then SUDO="sudo"; fi
command -v curl >/dev/null || { echo "updatool: curl is required" >&2; exit 1; }
command -v bash >/dev/null || { echo "updatool: bash is required" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "▸ downloading updatool ($REF)"
curl -fsSL "$URL" | tar -xz -C "$TMP"
SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
$SUDO rm -rf "$DEST"
$SUDO mkdir -p "$DEST" "$PREFIX/bin"
$SUDO cp -R "$SRC/bin" "$SRC/lib" "$SRC/presets" "$SRC/skills" "$DEST/"
$SUDO chmod +x "$DEST/bin/updatool"
$SUDO ln -sf "$DEST/bin/updatool" "$PREFIX/bin/updatool"
echo "✔ installed: $("$PREFIX/bin/updatool" --version) → $PREFIX/bin/updatool"
echo "  next: cd your-app && updatool init"
