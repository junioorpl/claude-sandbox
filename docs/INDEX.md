# Docs index

Starting points for the deeper design behind claude-sandbox.

## Specs

- [superpowers/specs/2026-04-17-claude-dev-sandbox-design.md](./superpowers/specs/2026-04-17-claude-dev-sandbox-design.md) — original design rationale. Answers "why fork Anthropic's devcontainer? why per-org volumes? why a shared CLI volume?"

## Plans (shipped)

- [superpowers/plans/2026-04-17-claude-dev-sandbox-implementation.md](./superpowers/plans/2026-04-17-claude-dev-sandbox-implementation.md) — the 9-phase KERNEL implementation plan the first release was built from.

## Operational docs (repo root)

- [../README.md](../README.md) — user-facing quickstart + roadmap
- [../RELEASING.md](../RELEASING.md) — semver rules, channel guidance, rollback
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — fork flow, upstream resync
- [../SECURITY.md](../SECURITY.md) — disclosure channel + scope
- [../.devcontainer/UPSTREAM.md](../.devcontainer/UPSTREAM.md) — upstream drift log

## Examples

- [../.claude/settings.json.example](../.claude/settings.json.example) — sandbox-friendly Claude Code settings
- [../.claude/CLAUDE.md.example](../.claude/CLAUDE.md.example) — sandbox context block to paste into your host CLAUDE.md
- [../compose.override.example.yml](../compose.override.example.yml) — local-only compose tweaks (custom mounts, MCP sidecars, firewall refresh interval)
- [../.env.example](../.env.example) — per-org environment template
