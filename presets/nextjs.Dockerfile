# syntax=docker/dockerfile:1
# updatool preset — Next.js (output: "standalone")
# next.config: typescript.ignoreBuildErrors = true   (type check runs in CHECK_CMD)
#   Do NOT enable experimental.turbopackFileSystemCacheForBuild for production
#   builds: measured on Next 16.2.1 and 16.4.0, ~1 in 3 warm builds missed the
#   change to globals.css and shipped the previous release's CSS (see
#   docs/METHODOLOGY.md, "A cache must prove it is fresh").
# scripts/build-next.sh = presets/nextjs-build.sh (proves the CSS is fresh)
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm npm ci

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
# Cold compile on purpose (no Turbopack disk cache, see above). The speed comes
# from the npm cache mount and from moving the type check to CHECK_CMD.
# If you ever re-enable the compiler cache, mount it with sharing=locked:
#   RUN --mount=type=cache,target=/app/.next/cache,sharing=locked ...
# and keep build-next.sh: it rebuilds cold when the cache hands back stale CSS.
ARG APP_VERSION
RUN APP_VERSION="$APP_VERSION" sh scripts/build-next.sh

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
RUN addgroup -S app && adduser -S app -G app
COPY --from=builder /app/public ./public
COPY --from=builder --chown=app:app /app/.next/standalone ./
COPY --from=builder --chown=app:app /app/.next/static ./.next/static
USER app
EXPOSE 3000
CMD ["node", "server.js"]
