#!/usr/bin/env bash
# Vendors arra-oracle-v3 at the pinned V3_REF — full tree, same as
# arra-oracle/fetch-vendor.sh. A slim frontend-only vendor was tried and
# abandoned: the SPA imports the repo root's package.json and reaches into
# backend src/ from 15 files, so the only build layout that provably works
# is the same one the backend image uses.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

REF="$(cat ../V3_REF)"
rm -rf vendor
git clone --quiet https://github.com/Soul-Brews-Studio/arra-oracle-v3 vendor
git -C vendor checkout --quiet "${REF}"
rm -rf vendor/.git

echo "vendored arra-oracle-v3 @ ${REF}"
