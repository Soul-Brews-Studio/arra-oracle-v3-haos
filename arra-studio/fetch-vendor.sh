#!/usr/bin/env bash
# Vendors just the frontend of arra-oracle-v3 at the pinned V3_REF — the
# only piece of app source this add-on's image needs. Same pin file as
# arra-oracle/fetch-vendor.sh so both add-ons ship the same Studio.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

REF="$(cat ../V3_REF)"
rm -rf vendor
git clone --quiet https://github.com/Soul-Brews-Studio/arra-oracle-v3 vendor
git -C vendor checkout --quiet "${REF}"
rm -rf vendor/.git

# Keep only what the Dockerfile copies.
find vendor -mindepth 1 -maxdepth 1 ! -name frontend -exec rm -rf {} +

echo "vendored arra-oracle-v3 frontend @ ${REF}"
