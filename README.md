# arra-oracle-v3-haos

Home Assistant add-on packaging for [arra-oracle-v3](https://github.com/Soul-Brews-Studio/arra-oracle-v3)
— the Docker-first MCP memory + search platform, as a Supervisor add-on: Studio UI in the
sidebar via ingress, MCP/HTTP on a LAN port, corpus under /data so it rides in HA backups.

The app repo stays pure; this repo pins a `V3_REF`, builds per-arch images in CI, and owns
the release cadence. Plan: see haos-oracle docs/arra-v3-addon-plan.md.
