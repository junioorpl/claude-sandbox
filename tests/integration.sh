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
# GH_TOKEN from runner env (CI) is inherited via docker compose env-from-shell.
GH_TOKEN=${GH_TOKEN:-}
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

echo "[7/7] Verify fail-loud REPOS bootstrap logic"
# We can't reuse the compose service entrypoint here because it ends in
# `exec zsh` which won't terminate under a non-TTY CI runner. Replay the
# bootstrap loop inline on a throwaway container — same logic, same fail
# mode (git clone exits non-zero, loop exits 1 before any later step).
bootstrap_out=$(ORG="$ORG" docker compose run --rm -T --entrypoint bash dev -lc '
  REPOS="git@github.com:nonexistent/repo-that-absolutely-does-not-exist-12345.git"
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    name=$(basename -s .git "$url")
    if [ ! -d "/tmp/$name" ]; then
      echo "[bootstrap] cloning $url"
      if ! git clone --no-tags --depth=1 "$url" "/tmp/$name" 2>&1; then
        echo "[bootstrap] ERROR failed to clone $url" >&2
        exit 1
      fi
    fi
  done < <(printf "%s\n" "$REPOS" | tr " " "\n")
' 2>&1 || true)
if echo "$bootstrap_out" | grep -q '\[bootstrap\] ERROR failed to clone'; then
  echo "REPOS bootstrap correctly exits non-zero on clone failure"
else
  echo "ERROR: bootstrap did not fail as expected; output was:" >&2
  echo "$bootstrap_out" | tail -20 >&2
  exit 1
fi

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
