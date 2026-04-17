#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# FIREWALL_REFRESH=1 skips ipset/iptables teardown + re-applies allowlist only.
# Used by the background refresh loop started in init-firewall-wrapper.sh.
REFRESH_MODE="${FIREWALL_REFRESH:-0}"

resolve_and_add() {
  local domain="$1"
  local ips
  ips=$(dig +noall +answer +time=3 +tries=2 A "$domain" | awk '$4=="A" {print $5}')
  if [ -z "$ips" ]; then
    if [ "$REFRESH_MODE" = "1" ]; then
      echo "[refresh] WARN failed to resolve $domain; keeping prior entries"
      return 0
    fi
    echo "ERROR: Failed to resolve $domain"
    exit 1
  fi
  while IFS= read -r ip; do
    if [[ ! "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      echo "ERROR: Invalid IP from DNS for $domain: $ip"
      exit 1
    fi
    # -exist makes re-adds idempotent; needed for refresh mode.
    ipset add allowed-domains "$ip" -exist
    [ "$REFRESH_MODE" = "1" ] || echo "Adding $ip for $domain"
  done <<< "$ips"
}

if [ "$REFRESH_MODE" != "1" ]; then
  # 1. Extract Docker DNS info BEFORE any flushing
  DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

  # Flush existing rules and delete existing ipsets
  iptables -F
  iptables -X
  iptables -t nat -F
  iptables -t nat -X
  iptables -t mangle -F
  iptables -t mangle -X
  ipset destroy allowed-domains 2>/dev/null || true

  # 2. Selectively restore ONLY internal Docker DNS resolution
  if [ -n "$DOCKER_DNS_RULES" ]; then
      echo "Restoring Docker DNS rules..."
      iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
      iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
      echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
  else
      echo "No Docker DNS rules to restore"
  fi

  # First allow DNS and localhost before any restrictions
  # Allow outbound DNS
  iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
  # Allow inbound DNS responses
  iptables -A INPUT -p udp --sport 53 -j ACCEPT
  # Allow outbound SSH
  iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
  # Allow inbound SSH responses
  iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
  # Allow localhost
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A OUTPUT -o lo -j ACCEPT

  # Create ipset with CIDR support
  ipset create allowed-domains hash:net
fi

# Fetch GitHub meta information and aggregate + add their IP ranges.
# Uses GH_TOKEN (from per-org env) when available to avoid anonymous rate limits.
# Retries up to 3 times on transient failures.
echo "Fetching GitHub IP ranges..."
auth_header=()
if [ -n "${GH_TOKEN:-}" ]; then
    auth_header=(-H "Authorization: Bearer $GH_TOKEN")
fi

gh_ranges=""
for attempt in 1 2 3; do
    gh_ranges=$(curl -sSL --max-time 10 "${auth_header[@]}" \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: claude-sandbox" \
        https://api.github.com/meta) || gh_ranges=""
    if echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
        break
    fi
    echo "attempt $attempt: GitHub meta fetch failed or missing fields; retrying..."
    echo "  response head: $(echo "$gh_ranges" | head -c 200)"
    sleep $((attempt * 2))
    gh_ranges=""
done

if [ -z "$gh_ranges" ]; then
    if [ "$REFRESH_MODE" = "1" ]; then
        echo "[refresh] WARN GitHub meta fetch failed; keeping prior ipset entries"
    else
        echo "ERROR: GitHub meta fetch failed after retries (hint: set GH_TOKEN in orgs/<org>/.env to avoid rate limits)"
        exit 1
    fi
else
    echo "Processing GitHub IPs..."
    while read -r cidr; do
        if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
            exit 1
        fi
        [ "$REFRESH_MODE" = "1" ] || echo "Adding GitHub range $cidr"
        ipset add allowed-domains "$cidr" -exist
    done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)
fi

# Resolve and add the default allowed domains.
# Multi-A capture: resolve_and_add() adds every A record, not just the first.
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "sentry.io" \
    "statsig.anthropic.com" \
    "statsig.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com"; do
    [ "$REFRESH_MODE" = "1" ] || echo "Resolving $domain..."
    resolve_and_add "$domain"
done

# Extra per-org allowed domains from EXTRA_ALLOWED_DOMAINS env.
# Accepts newline- or space-delimited list.
if [ -n "${EXTRA_ALLOWED_DOMAINS:-}" ]; then
    while IFS= read -r domain; do
        [ -z "$domain" ] && continue
        [ "$REFRESH_MODE" = "1" ] || echo "Resolving extra domain $domain..."
        resolve_and_add "$domain"
    done < <(printf '%s\n' "$EXTRA_ALLOWED_DOMAINS" | tr ' ' '\n')
fi

# Refresh mode stops here — iptables rules + IPv6 already configured on first run.
if [ "$REFRESH_MODE" = "1" ]; then
    echo "[refresh] allowlist refresh complete ($(ipset list allowed-domains | grep -c '^[0-9]') entries)"
    exit 0
fi

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Rate-limited log of drops for doctor surface + debugging.
iptables -N FW_DROP 2>/dev/null || true
iptables -F FW_DROP
iptables -A FW_DROP -m limit --limit 5/min --limit-burst 10 \
    -j LOG --log-prefix "fw-drop: " --log-level 4
iptables -A FW_DROP -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -j FW_DROP

# IPv6 policy — allow or deny as a whole. Default: deny-all to avoid a silent
# bypass when DNS returns AAAA records that aren't in the IPv4 allowlist.
# Opt in with IPV6=allow in orgs/<org>/.env when a specific workflow needs it.
IPV6_MODE="${IPV6:-deny}"
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -F 2>/dev/null || true
    ip6tables -X 2>/dev/null || true
    if [ "$IPV6_MODE" = "allow" ]; then
        echo "[firewall] IPv6 explicitly allowed via IPV6=allow — outbound unrestricted on v6"
        ip6tables -P INPUT ACCEPT
        ip6tables -P OUTPUT ACCEPT
        ip6tables -P FORWARD ACCEPT
    else
        ip6tables -P INPUT DROP
        ip6tables -P FORWARD DROP
        ip6tables -P OUTPUT DROP
        ip6tables -A INPUT -i lo -j ACCEPT
        ip6tables -A OUTPUT -o lo -j ACCEPT
        ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        echo "[firewall] IPv6 deny-all (default). Set IPV6=allow to opt in."
    fi
else
    echo "[firewall] ip6tables not available; skipping IPv6 policy"
fi

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi
