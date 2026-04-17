# claude-sandbox

Portable, per-organization isolated Docker environment for running [Claude Code](https://github.com/anthropics/claude-code) with `--dangerously-skip-permissions` safely.

Fork of Anthropic's reference devcontainer, wrapped with a per-org launcher, Docker Compose services, and a shared Claude CLI volume that supports hot upgrades without rebuilding images or restarting containers.

## Status

Design phase. See [design spec](./docs/superpowers/specs/2026-04-17-claude-dev-sandbox-design.md). Implementation plan coming next.

## Why

- **`--dangerously-skip-permissions` without risk** — container isolation + firewall allowlist
- **Per-organization isolation** — separate volumes for credentials, projects, and workspace; zero cross-org contamination
- **Shared plugins and settings** — your host `~/.claude/plugins`, `skills`, and `settings.json` propagate into every container
- **Hot CLI upgrades** — `claude-sandbox upgrade` bumps the Claude CLI in a shared volume; running containers pick it up on next invocation
- **Shareable across machines** — clone the repo, pull the prebuilt image from GHCR, drop in a per-org `.env`, and you're running in under a minute

## Quick start

> Coming with the implementation. See the [design spec](./docs/superpowers/specs/2026-04-17-claude-dev-sandbox-design.md) for the current plan.

```bash
git clone git@github.com:junioorpl/claude-sandbox.git ~/claude-sandbox
cd ~/claude-sandbox
cp .env.example orgs/personal/.env && $EDITOR orgs/personal/.env
./bin/claude-sandbox personal
# inside container:
git clone <your-repo>
cd <your-repo>
claude --dangerously-skip-permissions
```

## Architecture

See [`docs/superpowers/specs/`](./docs/superpowers/specs/) for the full design document.

High-level:

- **Base image**: fork of `anthropics/claude-code/.devcontainer` — Node 20 slim, firewall allowlist, git, zsh, fzf
- **Per-org named volumes**: `claude-data-<org>`, `workspace-<org>`
- **Shared host bind-mounts**: plugins, skills, settings, CLAUDE.md, Obsidian vault (optional)
- **Shared CLI volume**: `claude-cli-bin` — live-upgradeable without container restart
- **Launcher**: `bin/claude-sandbox <org>` drops you into an interactive shell with the right context

## License

MIT — see [LICENSE](./LICENSE).

Credit to Anthropic for the [reference devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer) that this project extends.
