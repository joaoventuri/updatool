# syntax=docker/dockerfile:1
# updatool preset — Next.js (output: "standalone")
# next.config: experimental.turbopackFileSystemCacheForBuild = true
#              typescript.ignoreBuildErrors = true   (type check runs in CHECK_CMD)
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
# .next/cache survives between builds: a one-line change compiles in seconds.
# sharing=locked: two builds never write the compiler cache at the same time.
# build-next.sh rebuilds cold if the cache ever hands back stale CSS.
ARG APP_VERSION
RUN --mount=type=cache,target=/app/.next/cache,sharing=locked \
    APP_VERSION="$APP_VERSION" sh scripts/build-next.sh

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
