#!/usr/bin/env bash
# tests/integration.sh — end-to-end smoke test + cross-org isolation.
# Requires local docker + built image (or pulled from GHCR).
set -euo pipefail

cd "$(dirname "$0")/.."

ORG="integrationtest"
mkdir -p "orgs/$ORG"
cat > "orgs/$ORG/.env" <<EOF
GIT_USER_NAME=IntegrationTest
GIT_USER_EMAIL=integration@test.local
FIREWALL=on
CLAUDE_CLI_VERSION=latest
EOF

# BRAIN_PATH defaults handled by launcher; for direct compose invocations below
# we set it to a scratch dir so the compose parser is happy.
export BRAIN_PATH="${BRAIN_PATH:-$(mktemp -d)}"

trap 'rm -rf "orgs/'"$ORG"'"; docker volume rm -f "claude-data-'"$ORG"'" "workspace-'"$ORG"'" >/dev/null 2>&1 || true' EXIT

echo "[1/7] Build image"
ORG="$ORG" docker compose build dev

echo "[2/7] Populate CLI volume"
./bin/claude-sandbox upgrade latest

echo "[3/7] Verify claude --version in dev service"
ORG="$ORG" docker compose run --rm --entrypoint /opt/claude-cli/bin/claude dev --version

echo "[4/7] Verify firewall allows GitHub"
ORG="$ORG" docker compose run --rm --entrypoint bash dev -lc \
  'sudo /usr/local/bin/init-firewall-wrapper.sh && curl --connect-timeout 5 https://api.github.com/zen'

echo "[5/7] Verify firewall blocks example.com"
ORG="$ORG" FIREWALL=on docker compose run --rm --entrypoint bash dev -lc \
  'sudo /usr/local/bin/init-firewall-wrapper.sh && ! curl --connect-timeout 5 https://example.com'

echo "[6/7] Verify IPv6 deny-all by default"
ORG="$ORG" FIREWALL=on docker compose run --rm --entrypoint bash dev -lc \
  'sudo /usr/local/bin/init-firewall-wrapper.sh && \
   if command -v ip6tables >/dev/null 2>&1; then \
     policy=$(sudo ip6tables -S OUTPUT | head -1); \
     echo "ip6tables OUTPUT policy: $policy"; \
     [[ "$policy" == *"DROP"* ]]; \
   else \
     echo "ip6tables not available; skipping"; \
   fi'

echo "[7/7] Verify fail-loud REPOS bootstrap on bad URL"
ORG="$ORG" REPOS="git@github.com:nonexistent/repo-that-does-not-exist.git" \
  docker compose run --rm --entrypoint bash dev -lc 'echo should-not-reach' \
  && { echo "ERROR: bad REPOS should have failed but didn't" >&2; exit 1; } \
  || echo "REPOS bootstrap correctly exits non-zero on clone failure"

echo "OK"

# --- Cross-org isolation -----------------------------------------------------
echo "[iso 1/3] Set up two orgs with distinct markers"
mkdir -p orgs/iso-a orgs/iso-b
cat > orgs/iso-a/.env <<EOF
GIT_USER_NAME=A
GIT_USER_EMAIL=a@a
FIREWALL=off
EOF
cat > orgs/iso-b/.env <<EOF
GIT_USER_NAME=B
GIT_USER_EMAIL=b@b
FIREWALL=off
EOF
ORG=iso-a docker compose run --rm --entrypoint bash dev -lc \
  'echo a-marker > /home/node/.claude/MARK-A; echo a-workspace > /workspace/MARK-A'

echo "[iso 2/3] Confirm org B cannot see org A's markers in either volume"
ORG=iso-b docker compose run --rm --entrypoint bash dev -lc \
  'test ! -f /home/node/.claude/MARK-A && test ! -f /workspace/MARK-A'

echo "[iso 3/3] Cleanup"
for org in iso-a iso-b; do
  rm -rf "orgs/$org"
  docker volume rm -f "claude-data-$org" "workspace-$org" >/dev/null 2>&1 || true
done
echo "ISOLATION OK"
