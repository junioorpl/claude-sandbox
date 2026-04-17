#!/bin/bash
# init-firewall-wrapper.sh
# Honors per-org FIREWALL env var; default on.
set -euo pipefail

FIREWALL="${FIREWALL:-on}"

if [ "$FIREWALL" = "off" ]; then
  echo "[firewall] Disabled via FIREWALL=off. Container has unrestricted outbound access."
  exit 0
fi

if [ "$FIREWALL" != "on" ]; then
  echo "[firewall] ERROR: invalid FIREWALL value '$FIREWALL' (expected 'on' or 'off')" >&2
  exit 1
fi

exec /usr/local/bin/init-firewall.sh
