#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
#
# Reads the Studio add-on's options and starts the proxy server.

set -eu

ORACLE_URL="$(bashio::config 'oracle_url')"
ORACLE_API_KEY="$(bashio::config 'oracle_api_key')"

[ "${ORACLE_URL}" = "null" ] && ORACLE_URL=""
[ "${ORACLE_API_KEY}" = "null" ] && ORACLE_API_KEY=""

if [ -z "${ORACLE_API_KEY}" ]; then
    bashio::log.fatal "oracle_api_key is not set."
    bashio::log.fatal "Set it to the Arra Oracle backend add-on's owner_api_key —"
    bashio::log.fatal "Studio cannot authenticate to the backend without it."
    exit 1
fi

if [ -z "${ORACLE_URL}" ]; then
    bashio::log.fatal "oracle_url is not set."
    exit 1
fi

export ORACLE_URL
export ORACLE_API_KEY
export PORT=8100
export STUDIO_DIST=/app/frontend/dist

bashio::log.info "Arra Studio starting"
bashio::log.info "  backend: ${ORACLE_URL}"
bashio::log.info "  port:    8100 (sidebar launcher + session-gated LAN Studio)"

# exec so bun receives s6's stop signals directly.
exec bun /app/server.ts
