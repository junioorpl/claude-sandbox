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
| devcontainer.json | Removed `workspaceMount` | No host project bind-mount; code cloned inside container |
| devcontainer.json | Added shared-CLI, per-org, and host-subpath mounts | Multi-org isolation + host plugin propagation |
| devcontainer.json | `postStartCommand` calls `init-firewall-wrapper.sh` | Honor `FIREWALL=off` opt-out |
| init-firewall.sh | Added `EXTRA_ALLOWED_DOMAINS` resolution block | Per-org domain extensions |
| init-firewall-wrapper.sh | New file | Firewall on/off toggle |

## Resync procedure

When upstream updates:

1. `gh api repos/anthropics/claude-code/commits/main --jq .sha` → record new SHA
2. Diff `/tmp/cc-upstream/<file>` against `.devcontainer/<file>` for each of the three forked files
3. Reapply our drift deltas from the table above on top of the new upstream version
4. Update this file with the new upstream SHA
5. Run the full bats + integration suite before committing
