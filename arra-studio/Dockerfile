# Arra Studio add-on — the Studio SPA plus a ~180-line bun proxy server.
# Much smaller than the backend image: no app runtime, no migrations, just
# the built frontend and server.ts. Source for the frontend build comes from
# vendor/ at the same pinned V3_REF (fetch-vendor.sh, shared with
# arra-oracle/), so both add-ons always ship the same Studio.
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.22@sha256:0eda502b4d16e0433ace512d857ec3e86497d4214091ee459078ee4df6373f63
FROM ${BUILD_FROM}

ARG BUILD_VERSION="dev"
ARG BUILD_ARCH="amd64"

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}"

RUN apk add --no-cache libstdc++ unzip curl \
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

# The SPA imports the repo root's package.json (SimplePage shows the app
# version), so the root manifest must sit one level above frontend/. Its
# workspaces list has to go, though — bun install inside frontend/ walks up,
# adopts this manifest as the workspace root, and refuses to run without
# the sibling workspace dirs the slim vendor deliberately lacks.
COPY vendor/package.json ./package.json
RUN bun -e "const p = await Bun.file('package.json').json(); delete p.workspaces; await Bun.write('package.json', JSON.stringify(p, null, 2));"
COPY vendor/frontend ./frontend
RUN cd frontend \
 && bun install \
 && bunx vite build \
 && test -s dist/index.html \
 && rm -rf node_modules src

COPY server.ts ./server.ts
COPY run.sh /run.sh
RUN chmod 0755 /run.sh

CMD ["/run.sh"]
