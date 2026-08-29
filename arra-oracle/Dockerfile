# Single-process embedded mode: main server only, no vector sidecar, no
# indexer daemon, no python reranker (v3 can run FOUR processes; an add-on
# wants one — see docs/arra-v3-addon-plan.md §1). Mirrors v3's own
# production Dockerfile stages (bun install --production, bun build --target
# bun, copy migrations separately) but on the HA base image so bashio/s6 own
# the container, matching arra-memory-haos's pattern.
#
# Source comes from vendor/ (fetched by fetch-vendor.sh / the builder
# workflow at the pinned V3_REF, never committed) — the app repo stays pure.
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.22@sha256:0eda502b4d16e0433ace512d857ec3e86497d4214091ee459078ee4df6373f63
FROM ${BUILD_FROM}

ARG BUILD_VERSION="dev"
ARG BUILD_ARCH="amd64"

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}"

# libstdc++ for bun itself; python3/make/g++ because v3's vector adapters
# (sqlite-vec, lancedb) carry native bindings that may need a build fallback
# when no prebuilt musl binary exists for the target arch.
RUN apk add --no-cache libstdc++ unzip curl jq python3 make g++ \
 && case "${BUILD_ARCH}" in \
      amd64)   BUN_TARGET="bun-linux-x64-musl" ;; \
      aarch64) BUN_TARGET="bun-linux-aarch64-musl" ;; \
      *)       echo "unsupported arch: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL --retry 4 --retry-delay 2 --retry-all-errors "https://github.com/oven-sh/bun/releases/latest/download/${BUN_TARGET}.zip" -o /tmp/bun.zip \
 && unzip -q /tmp/bun.zip -d /tmp \
 && mv "/tmp/${BUN_TARGET}/bun" /usr/local/bin/bun \
 && chmod +x /usr/local/bin/bun \
 && ln -s bun /usr/local/bin/bunx \
 && rm -rf /tmp/bun.zip "/tmp/${BUN_TARGET}" \
 && bun --version

WORKDIR /app

# Dependencies first — matches v3's own "deps" stage inputs so bun's
# workspace resolution sees the same package.json set.
COPY vendor/package.json vendor/bun.lock ./
COPY vendor/frontend/package.json ./frontend/package.json
COPY vendor/workers/mcp/package.json ./workers/mcp/package.json
RUN bun install --production --frozen-lockfile

COPY vendor/tsconfig.json ./
COPY vendor/packages ./packages
COPY vendor/src ./src

# Same bundle v3's own Dockerfile produces — dist/server.js is the one
# process this add-on runs. dist-cli/index.js is NOT built: the `arra` CLI
# and bin/mcp.ts stdio mode have no place in an add-on (Supervisor is the
# process manager; MCP clients use the HTTP /mcp routes instead).
RUN bun build src/server.ts --target bun --outdir dist

# Migrations run at boot (initializeDrizzleSqlite), so they must exist on
# disk next to the running server, not just inside the bundle.
COPY vendor/src/db/migrations ./db/migrations

# The Studio UI. Upstream's own production image never builds frontend/dist —
# its containers serve JSON only (spa.ts falls through when the dir is
# missing). This add-on puts Studio in the HA sidebar via ingress, so the
# React app is built here and pointed at with ORACLE_FRONTEND_DIST in run.sh.
COPY vendor/frontend ./frontend
RUN cd frontend \
 && bun install \
 && bunx vite build \
 && test -s dist/index.html \
 && rm -rf node_modules

COPY run.sh /run.sh
RUN chmod 0755 /run.sh

CMD ["/run.sh"]
