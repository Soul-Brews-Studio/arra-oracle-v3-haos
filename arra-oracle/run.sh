#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
#
# Reads this add-on's Supervisor options and starts v3's main server in
# embedded mode. Options are read HERE, at container start, never baked into
# the image — same reasoning as arra-memory-haos/run.sh.

set -eu

OWNER_API_KEY="$(bashio::config 'owner_api_key')"
API_TOKEN="$(bashio::config 'api_token')"
SESSION_SECRET="$(bashio::config 'session_secret')"
PUBLIC_URL="$(bashio::config 'public_url')"
EMBEDDER="$(bashio::config 'embedder')"
EMBEDDER_URL="$(bashio::config 'embedder_url')"
EMBEDDING_MODEL="$(bashio::config 'embedding_model')"
VECTOR_DB="$(bashio::config 'vector_db')"
VECTOR_FALLBACK="$(bashio::config 'vector_fallback')"
FILE_WATCHER="$(bashio::config 'file_watcher')"
CONSOLIDATION="$(bashio::config 'consolidation')"
HUGINN_CAPTURE="$(bashio::config 'huginn_capture')"
LOG_FORMAT_OPT="$(bashio::config 'log_format')"
ARRA_ENV_OPT="$(bashio::config 'arra_env')"
DEBUG_OPT="$(bashio::config 'debug')"

# bashio renders an unset optional string as the literal "null" — a
# perfectly valid, completely wrong value if exported as-is.
[ "${API_TOKEN}" = "null" ] && API_TOKEN=""
[ "${PUBLIC_URL}" = "null" ] && PUBLIC_URL=""
[ "${EMBEDDER_URL}" = "null" ] && EMBEDDER_URL=""

if [ -z "${OWNER_API_KEY}" ]; then
    bashio::log.fatal "owner_api_key is not set."
    bashio::log.fatal "v3's own default (ARRA_API_KEY='') disables auth entirely."
    bashio::log.fatal "Open this add-on's Configuration tab and set one:"
    bashio::log.fatal "    openssl rand -base64 32"
    bashio::log.fatal "Refusing to start unauthenticated on a LAN port."
    exit 1
fi

if [ -z "${SESSION_SECRET}" ]; then
    bashio::log.fatal "session_secret is not set."
    bashio::log.fatal "v3's own default (randomUUID()) invalidates every session on"
    bashio::log.fatal "restart, silently. Set one:"
    bashio::log.fatal "    openssl rand -base64 32"
    exit 1
fi

# /data is the only path Supervisor persists across restarts and includes in
# Home Assistant's backups. HOME=/data funnels every v3-derived path there.
export HOME=/data
export ORACLE_DATA_DIR=/data/oracle
export ORACLE_PORT=47778
export PORT=47778
export NODE_ENV=production
# Studio UI built into the image — upstream containers omit it entirely.
export ORACLE_FRONTEND_DIST=/app/frontend/dist

export ARRA_API_KEY="${OWNER_API_KEY}"
export ARRA_API_TOKEN="${API_TOKEN}"
export ORACLE_SESSION_SECRET="${SESSION_SECRET}"
export ORACLE_URL="${PUBLIC_URL}"
export ORACLE_EMBEDDER="${EMBEDDER}"
export OLLAMA_BASE_URL="${EMBEDDER_URL}"
export ORACLE_EMBEDDER_URL="${EMBEDDER_URL}"
export ORACLE_EMBEDDING_MODEL="${EMBEDDING_MODEL}"
export ORACLE_VECTOR_DB="${VECTOR_DB}"
export VECTOR_FALLBACK="${VECTOR_FALLBACK}"
export ORACLE_FILE_WATCHER="${FILE_WATCHER}"
export ORACLE_CONSOLIDATION_WORKER="${CONSOLIDATION}"
export ARRA_HUGINN_CAPTURE="${HUGINN_CAPTURE}"
export LOG_FORMAT="${LOG_FORMAT_OPT}"
# Pinned regardless of ARRA_ENV: fixes the live upstream bug where every
# "production" v3 deploy silently runs the development profile (no compose
# sets this var) — rate limiting stays OFF otherwise. See
# docs/arra-v3-addon-plan.md §5.
export ARRA_ENV="${ARRA_ENV_OPT}"
export DEBUG="${DEBUG_OPT}"
export ARRA_VERBOSE_LOGGING="${DEBUG_OPT}"

# The daemon/autostart machinery is irrelevant here — Supervisor is the
# process manager, not ensure-server.ts. This is the true kill switch (0
# kills both the embedded and lazy paths; a flag that only disables warming
# is not a kill switch).
export ORACLE_MCP_AUTOSTART_HTTP=0
export ORACLE_TOOL_GROUPS_HOT_RELOAD=0
export ARRA_PLUGIN_HOT_RELOAD=0

bashio::log.info "Arra Oracle starting"
bashio::log.info "  data:     /data/oracle"
bashio::log.info "  profile:  ${ARRA_ENV}"
if bashio::var.has_value "${API_TOKEN}"; then
    bashio::log.info "  auth:     owner key + static API token"
else
    bashio::log.info "  auth:     owner key only (api_token not set)"
fi
if [ "${EMBEDDER}" != "none" ]; then
    bashio::log.info "  search:   keyword (FTS5) + semantic via ${EMBEDDER} (${EMBEDDING_MODEL})"
else
    bashio::log.info "  search:   keyword only (FTS5) — set embedder to enable semantic search"
fi
bashio::log.info "  vector:   ${VECTOR_DB} (fallback: ${VECTOR_FALLBACK})"
if bashio::var.has_value "${PUBLIC_URL}"; then
    bashio::log.info "  public:   ${PUBLIC_URL}"
fi

# exec so bun becomes PID 1 of this process tree and receives the signals s6
# sends on stop, instead of waiting out the kill timeout on every restart.
exec bun /app/dist/server.js
