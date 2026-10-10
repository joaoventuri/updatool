# syntax=docker/dockerfile:1
# updatool preset — Rust (cargo). The target dir is cached, so copy the binary out.
FROM rust:1-slim AS build
WORKDIR /src
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --release && cp target/release/app /app

FROM debian:bookworm-slim
COPY --from=build /app /usr/local/bin/app
EXPOSE 8080
CMD ["app"]
