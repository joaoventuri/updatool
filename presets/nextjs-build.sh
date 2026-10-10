#!/bin/sh
# updatool preset — next build with the Turbopack disk cache AND proof that the
# CSS is fresh. Copy to scripts/build-next.sh (used by presets/nextjs.Dockerfile).
#
# turbopackFileSystemCacheForBuild turns a ~4 min build into ~30-60 s, but it is
# experimental: in production we saw (once, not reproducible) an image ship with
# the new JS and the previous release's CSS, byte for byte. So the build does not
# trust the cache: it appends a unique marker rule to the global stylesheet,
# builds, and looks for the marker in .next/static. Missing marker = stale CSS
# from the cache → wipe the cache and build cold. Stale CSS never ships.
set -eu
CSS="${GLOBAL_CSS:-}"
if [ -z "$CSS" ]; then
  for f in src/app/globals.css app/globals.css src/styles/globals.css styles/globals.css; do
    if [ -f "$f" ]; then CSS="$f"; break; fi
  done
fi
if [ -z "$CSS" ]; then echo "build-next: no global CSS found (set GLOBAL_CSS)"; exec npm run build; fi

MARK="m$(printf '%s' "${APP_VERSION:-${GIT_SHA:-x}}" | tr -cd 'a-zA-Z0-9')$(date +%s)"
printf '\n/* build marker (updatool build-next.sh) */\n.updatool-build-%s { --updatool-build: 1; }\n' "$MARK" >> "$CSS"
fresh() { grep -rqs -- "updatool-build-$MARK" .next/static; }

npm run build
if fresh; then echo "build-next: fresh CSS confirmed ($MARK)"; exit 0; fi
echo "build-next: STALE CSS from the Turbopack cache — wiping the cache and building cold"
rm -rf .next/cache/* .next/cache/.[!.]* 2>/dev/null || true
find .next -mindepth 1 -maxdepth 1 ! -name cache -exec rm -rf {} +
npm run build
fresh || { echo "build-next: marker missing even after a cold build — aborting"; exit 1; }
echo "build-next: fresh CSS confirmed after a cold build"
