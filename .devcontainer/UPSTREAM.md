# Upstream reference

Forked from: https://github.com/anthropics/claude-code/tree/main/.devcontainer
Upstream commit at fork time: `2b53fac3b2dd`
License: upstream MIT (see project root LICENSE for this fork's license).

## Drift from upstream

| File | Change | Reason |
|---|---|---|
| Dockerfile | Removed `RUN npm install -g @anthropic-ai/claude-code` and `CLAUDE_CODE_VERSION` arg | CLI moved to shared volume for hot upgrades |
| Dockerfile | `NPM_CONFIG_PREFIX` retargeted from `/usr/local/share/npm-global` to `/opt/claude-cli` | Align npm prefix with mounted volume |
| Dockerfile | `PATH` now includes `/opt/claude-cli/bin` | Resolve `claude` from volume |
| Dockerfile | Pre-create `/brain` and `~/.claude/{plugins,skills,projects}` | Mount targets for per-org volumes and host bind-mounts |
| Dockerfile | git-delta .deb SHA256-verified per arch before `dpkg -i` | Supply-chain: no silent tamper |
| Dockerfile | zsh-in-docker install script vendored at `.devcontainer/zsh-in-docker.sh`, SHA256-verified at build time | Supply-chain: no `sh -c "$(wget -O- …)"` |
| Dockerfile | `FROM ${NODE_IMAGE}` driven by build-arg | Single source for base image across Dockerfile + compose cli-init |
| Dockerfile | `claude` wrapper at `/usr/local/bin/claude` always passes `--dangerously-skip-permissions` | Sandbox IS the boundary; avoid re-prompting inside |
| devcontainer.json | Removed `workspaceMount` | No host project bind-mount; code cloned inside container |
| devcontainer.json | Added shared-CLI, per-org, and host-subpath mounts | Multi-org isolation + host plugin propagation |
| devcontainer.json | `postStartCommand` calls `init-firewall-wrapper.sh` | Honor `FIREWALL=off` opt-out |
| devcontainer.json | `/brain` source uses `${localEnv:BRAIN_PATH:…empty-brain}` | Optional knowledge vault; fork-portable |
| init-firewall.sh | Added `EXTRA_ALLOWED_DOMAINS` resolution (newline- or space-delimited) | Per-org domain extensions |
| init-firewall.sh | `resolve_and_add()` captures every A record, not just the first | Handle CDN multi-A rotation |
| init-firewall.sh | IPv6 explicit policy: default deny-all via ip6tables, `IPV6=allow` escape hatch | Close silent AAAA bypass |
| init-firewall.sh | Refresh mode (`FIREWALL_REFRESH=1`) re-applies allowlist without teardown | Long-running containers stay accurate under A-record rotation |
| init-firewall.sh | Rate-limited `fw-drop: ` LOG chain ahead of REJECT | Visibility of blocked egress |
| init-firewall.sh | CIDR + IP regex validation before `ipset add` | Defend against malformed GitHub meta / DNS responses |
| init-firewall.sh | GitHub meta fetch retries 3× + uses `GH_TOKEN` when set + validates via `jq -e` | Avoid anonymous rate-limit flakes |
| init-firewall-wrapper.sh | New file | Firewall on/off toggle |
| init-firewall-wrapper.sh | Backgrounds a refresh loop every `FIREWALL_REFRESH_INTERVAL` (default 900s) | Long-running container freshness |

## Resync procedure

When upstream updates:

1. Record the new upstream SHA:
   ```bash
   gh api repos/anthropics/claude-code/commits/main --jq .sha
   ```
2. Compute the diff since our last-known upstream SHA, scoped to
   `.devcontainer/`:
   ```bash
   prev=2b53fac3b2dd   # or whatever this file shows
   new=<the SHA from step 1>
   gh api "repos/anthropics/claude-code/compare/$prev...$new" --jq \
     '.files[] | select(.filename | startswith(".devcontainer/")) | .filename'
   ```
3. For each changed file in `.devcontainer/`:
   - Pull the new upstream version into `/tmp/upstream/<filename>`.
   - Diff against our local copy, keeping every drift row in the table above
     preserved.
   - Cherry-pick the upstream changes that are *additive* (new apt packages,
     new install steps) and leave our drift intact.
4. Update this file:
   - Bump the "Upstream commit at fork time" line to `$new`.
   - Add or update rows in the drift table for any new deviation.
5. Bump `VERSION` (MINOR if the resync is additive, MAJOR if upstream
   reshaped the firewall or mount layout).
6. Run the full bats + integration suite before committing:
   ```bash
   bats tests/
   bash tests/integration.sh
   ```
7. Open the PR titled `chore(upstream): resync to <short-sha>` with the
   drift-table diff as the body.
