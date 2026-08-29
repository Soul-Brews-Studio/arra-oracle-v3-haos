#!/usr/bin/env bash
# Clones arra-oracle-v3 at the pinned V3_REF into arra-oracle/vendor/, the
# Docker build context's copy of the app source.
#
# The app repo stays pure — this repo pins the ref and owns the release
# cadence, so vendor/ is fetched here (CI and local `docker build` alike)
# rather than committed. Run this before a local `docker build`; the
# builder workflow runs it as a CI step.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

REF="$(cat ../V3_REF)"
rm -rf vendor
git clone --quiet https://github.com/Soul-Brews-Studio/arra-oracle-v3 vendor
git -C vendor checkout --quiet "${REF}"
rm -rf vendor/.git

echo "vendored arra-oracle-v3 @ ${REF}"
