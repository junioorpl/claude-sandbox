# Contributing

Thanks for looking at claude-sandbox. This is a small, focused project — the goal is a trustworthy Docker sandbox for running Claude Code with `--dangerously-skip-permissions`. Contributions that extend that goal are welcome.

## Ways to contribute

- **Report issues**: firewall bypasses, fork-breakage, supply-chain concerns, documentation gaps.
- **Propose features**: open an issue first so we can agree on shape before code.
- **Small fixes**: typos, doc clarifications, bug fixes — open a PR directly.

## Fork flow

```bash
gh repo fork junioorpl/claude-sandbox --clone
cd claude-sandbox
git checkout -b <type>/<short-description>
```

Branch prefixes:

- `feat/` — new capability
- `fix/` — bug fix
- `chore/` — maintenance, deps, formatting
- `docs/` — documentation only
- `ci/` — workflow changes

## Local development

```bash
# Prereqs: Docker Desktop 4.30+ (or Docker Engine 24+) with compose v2; bats-core; shellcheck
./bin/setup                           # create an org, pull image
./bin/claude-sandbox <org> --build    # rebuild local image

# Tests
bats tests/
bash tests/integration.sh
shellcheck bin/*.sh bin/claude-sandbox .devcontainer/*.sh
```

CI runs all three on every push. Run locally before opening a PR.

## Commit style

[Conventional commits](https://www.conventionalcommits.org/):

```
feat(launcher): add `ide` subcommand for one-command editor attach
fix(firewall): retry GitHub meta fetch on 403 rate-limit responses
chore(deps): bump actions/checkout to v4.2.3
```

## Versioning

The `VERSION` file drives image tags. Every PR touching any of:

- `.devcontainer/Dockerfile`
- `.devcontainer/init-firewall.sh`
- `docker-compose.yml` (volumes or environment sections)
- `bin/claude-sandbox` (public flag/subcommand interface)

**must** bump `VERSION` at minimum to the next minor version. CI enforces this. See [`RELEASING.md`](./RELEASING.md) for semver rules.

If the change is purely internal (comments, refactor that doesn't affect behavior), add `[skip-version-check]` to the PR description with one-line rationale.

## Upstream resync (maintainer)

This repo forks `anthropics/claude-code/.devcontainer`. When upstream changes land:

1. Fetch the new SHA:
   ```bash
   gh api repos/anthropics/claude-code/commits/main --jq .sha
   ```
2. Diff against the last synced SHA (stored in `.devcontainer/UPSTREAM.md`):
   ```bash
   git diff <prev-sha>..<new-sha> -- .devcontainer/
   ```
3. Cherry-pick or manually apply relevant changes.
4. Update `.devcontainer/UPSTREAM.md` with new SHA, date, and one-line rationale per deviation kept.
5. Bump `VERSION` if the resync brings breaking changes.
6. Open PR: `chore(upstream): resync to <short-sha>`.

## Security-sensitive changes

Changes touching the firewall, image supply chain, or mount layout need extra care. See [`SECURITY.md`](./SECURITY.md) for the disclosure channel and scope.

Before opening a PR that touches these areas:

- Run `tests/firewall.bats` and `tests/integration.sh`.
- Verify a fresh `./bin/claude-sandbox <org> --build` + `./bin/claude-sandbox <org> doctor` still passes.
- Document the change in the PR description with a "regression considered" line.

## Code style

- Shell: `set -euo pipefail`, POSIX where practical, bash where not. Run `shellcheck`.
- Docker: pin versions + verify checksums for every download. No `curl | sh`.
- YAML: 2-space indent, lowercase keys, no anchors unless they cut ≥10 lines.

## License

By contributing, you agree that your contributions are licensed under the MIT License (see [LICENSE](./LICENSE)).
