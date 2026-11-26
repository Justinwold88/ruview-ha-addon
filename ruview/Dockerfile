# syntax=docker/dockerfile:1
#
# RuView app image. Built by .github/workflows/build.yml from the repository
# root, with RuView's source checked out at ruview-src/ at the commit pinned
# in ruview/RUVIEW_COMMIT. Home Assistant pulls the published image and never
# builds this file itself.
#
# The builder stage mirrors RuView's docker/Dockerfile.rust layout (v2/
# collapsed into /build, vendored crates beside it) but builds only the
# sensing server, with MQTT.

ARG RUST_IMAGE=rust:1.89-bookworm
ARG RUNTIME_IMAGE=debian:bookworm-slim

FROM ${RUST_IMAGE} AS builder
WORKDIR /build
COPY ruview-src/v2/Cargo.toml ruview-src/v2/Cargo.lock ./
COPY ruview-src/v2/crates/ ./crates/
COPY ruview-src/v2/vendor/security/ ./vendor/security/
COPY ruview-src/vendor/ruvector/ /build/vendor/ruvector/
COPY ruview-src/vendor/rufield/ /vendor/rufield/
RUN cargo build --locked --release -p wifi-densepose-sensing-server --features mqtt \
 && strip target/release/sensing-server

FROM ${RUNTIME_IMAGE}
ARG BUILD_VERSION=dev
ARG BUILD_ARCH=unknown
ARG RUVIEW_COMMIT=unknown

# curl and jq: the start script reads the options and asks the Supervisor
# for the MQTT broker. ca-certificates: MQTT over TLS.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/sensing-server /app/sensing-server
COPY ruview-src/ui/ /app/ui/
COPY ruview/rootfs/ /

RUN set -e; \
    test -x /app/sensing-server; \
    test -x /usr/local/bin/ruview-run; \
    test -f /app/ui/index.html; \
    /app/sensing-server --help >/dev/null

LABEL \
  io.hass.name="RuView" \
  io.hass.description="Camera-free presence sensing from ESP32 Wi-Fi signals" \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}" \
  org.opencontainers.image.title="RuView app for Home Assistant" \
  org.opencontainers.image.source="https://github.com/Justinwold88/ruview-ha-addon" \
  org.opencontainers.image.licenses="MIT" \
  org.opencontainers.image.version="${BUILD_VERSION}" \
  dev.ruview.commit="${RUVIEW_COMMIT}"

# /health is open even when the API needs a token, and the server always
# listens on loopback, so this works in every exposure mode.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/health >/dev/null || exit 1

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/ruview-run"]
