#!/bin/bash
# init-firewall-wrapper.sh
# Honors per-org FIREWALL env var; default on.
# After initial apply, backgrounds a refresh loop so CDN-rotated A records
# stay in the allowlist without requiring a container restart.
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

# Initial apply (blocks until verified).
/usr/local/bin/init-firewall.sh

# Background refresh loop: re-resolve the allowlist every 15 minutes so
# CDN-fronted hosts (npm, VS Code marketplace, statsig) stay reachable as
# their A records rotate. ipset add -exist is idempotent; old entries stay
# in place (tiny extra allowlist surface, huge reliability win).
REFRESH_INTERVAL="${FIREWALL_REFRESH_INTERVAL:-900}"
if [ "$REFRESH_INTERVAL" -gt 0 ]; then
  (
    while sleep "$REFRESH_INTERVAL"; do
      FIREWALL_REFRESH=1 /usr/local/bin/init-firewall.sh >>/tmp/firewall-refresh.log 2>&1 || true
    done
  ) &
  disown || true
  echo "[firewall] refresh loop backgrounded (interval=${REFRESH_INTERVAL}s, log=/tmp/firewall-refresh.log)"
fi
