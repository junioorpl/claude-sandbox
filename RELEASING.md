# Releasing

The `VERSION` file is the source of truth for semver tags. CI publishes image tags from it; consumers pin whichever channel matches their risk tolerance.

## Version channels

Every build on `main` publishes:

| Tag | Meaning | Mutability |
|---|---|---|
| `:v1.2.3` (exact) | Pinned forever. Never moves. | immutable |
| `:v1.2` (minor) | Latest `1.2.x`. | patches only |
| `:v1` (major) | Latest `1.x.y`. | minor + patch |
| `:latest` | Latest release, any version. | everything |
| `:sha-<40-char>` | Tied to a specific commit. | immutable |

**Recommended consumer pins**:

- Personal use, always-latest: `:latest`
- Stable day-to-day work: `:v1` (auto-bump minor + patch, no surprise majors)
- Hard-pin for reproducibility: `:v1.2.3` or `:sha-<sha>`

## Semver rules

- **MAJOR** (breaking): firewall baseline change, mount layout change, launcher flag removed or renamed, Node major bump, env var removed.
- **MINOR** (additive): new launcher subcommand, new optional env var, new allowed-domain category, opt-in feature behind a build arg.
- **PATCH** (no contract change): internal refactor, dep bump, doc fix, test addition.

## Release flow

1. Merge your work to `main` via PR. The version-bump gate (in `hygiene.yml`) blocks PRs that touch sensitive paths without bumping `VERSION`.
2. `build-and-push.yml` auto-publishes all channels on push.
3. Immediately after merge, tag the commit:
   ```bash
   VERSION="$(tr -d '[:space:]' < VERSION)"
   git tag -a "v${VERSION}" -m "v${VERSION}"
   git push origin "v${VERSION}"
   ```
4. If MAJOR bump, open a release note on GitHub Releases summarizing breaking changes and the migration.

## Rollback

If a release introduces a regression:

1. Bump `VERSION` to the next patch (e.g., `1.2.3 → 1.2.4`) on a revert PR.
2. Merge — CI flips `:v1` and `:v1.2` and `:latest` to the new patch.
3. The broken `:v1.2.3` stays frozen; anyone pinned there is unaffected.

Never move an existing immutable tag.

## Sensitive paths (gated by CI)

A PR touching any of these without a `VERSION` bump fails CI:

- `.devcontainer/Dockerfile`
- `.devcontainer/init-firewall.sh`
- `.devcontainer/init-firewall-wrapper.sh`
- `docker-compose.yml`
- `bin/claude-sandbox`

Override with `[skip-version-check]` in the PR description plus a one-line rationale.

## Initial version

The project starts at **v1.1.0** (the first release under this versioning discipline). Earlier builds published only `:latest` and `:sha-<sha>` without semver channels.
