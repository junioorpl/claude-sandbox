# claude-sandbox

Portable, per-organization isolated Docker environment for running [Claude Code](https://github.com/anthropics/claude-code) with `--dangerously-skip-permissions` safely.

Fork of Anthropic's reference devcontainer, wrapped with a per-org launcher, Docker Compose services, and a shared Claude CLI volume that supports hot upgrades without rebuilding images or restarting containers.

## Why

- **`--dangerously-skip-permissions` without risk** — container isolation + firewall allowlist
- **Per-organization isolation** — separate volumes for credentials, projects, and workspace; zero cross-org contamination
- **Shared plugins and settings** — your host `~/.claude/plugins`, `skills`, and `settings.json` propagate into every container
- **Hot CLI upgrades** — `claude-sandbox upgrade` bumps the Claude CLI in a shared volume; running containers pick it up on next invocation
- **Shareable across machines** — clone the repo, pull the prebuilt image from GHCR, drop in a per-org `.env`, and you're running in under a minute

## Quick start

1. Prerequisites: Docker Desktop 4.30+ (or Docker Engine 24+) with `docker compose`.
2. Clone and set up:

   ```bash
   git clone git@github.com:junioorpl/claude-sandbox.git ~/claude-sandbox
   cd ~/claude-sandbox
   mkdir -p orgs/personal
   cp .env.example orgs/personal/.env
   $EDITOR orgs/personal/.env       # set GIT_USER_NAME, GIT_USER_EMAIL
   ```

3. Launch:

   ```bash
   ./bin/claude-sandbox personal
   ```

   First run populates the shared Claude CLI volume (~30s) and pulls the image from GHCR.

**Or just run the interactive setup:**

```bash
./bin/setup
# prompts for org name, git identity, optional shell alias install, optional editor pass, then launches
```

After the alias is installed (and `source ~/.zshrc` / new terminal), you can run `claude-sandbox <org>` from anywhere instead of the full `./bin/claude-sandbox …` path. Install or refresh it standalone via `./bin/install-alias`.

4. Inside the container:

   ```bash
   git clone git@github.com:you/your-repo.git
   cd your-repo
   claude                  # already runs with --dangerously-skip-permissions
   ```

   The sandbox **is** the isolation boundary, so `claude` inside any container
   is a wrapper that always passes `--dangerously-skip-permissions`. Call
   `/opt/claude-cli/bin/claude` if you ever need the raw CLI.

## Common tasks

```bash
./bin/claude-sandbox --list                   # list configured orgs
./bin/claude-sandbox upgrade                  # bump CLI to latest (no restart)
./bin/claude-sandbox upgrade 1.2.3            # pin to a version
./bin/claude-sandbox <org> throwaway          # ephemeral workspace
./bin/claude-sandbox <org> agent worker-1     # parallel named instance
./bin/claude-sandbox <org> vscode             # generate per-org devcontainer for VS Code
./bin/claude-sandbox doctor                   # diagnostics
./bin/claude-sandbox --no-host-mounts <org>   # hermetic run — no host bleed-through
```

## Multi-organization usage

Create `orgs/<name>/.env` for each organization:

```bash
mkdir -p orgs/acme
cp .env.example orgs/acme/.env
$EDITOR orgs/acme/.env   # set acme-specific git identity, EXTRA_ALLOWED_DOMAINS, etc.
./bin/claude-sandbox acme
```

Each org gets dedicated Docker volumes (`claude-data-<org>`, `workspace-<org>`). A container launched with `ORG=acme` cannot access `ORG=personal` volumes.

## Auto-cloning repos

Declare a `REPOS` list in `orgs/<org>/.env` to auto-clone repositories into `/workspace` on first launch:

```dotenv
REPOS="git@github.com:you/repo-a.git git@github.com:you/repo-b.git"
```

Clones are idempotent — existing dirs are skipped on subsequent launches. SSH URLs require the default `~/.ssh` bind-mount.

## Architecture

See [`docs/superpowers/specs/`](./docs/superpowers/specs/) for the full design document and [`docs/superpowers/plans/`](./docs/superpowers/plans/) for the KERNEL-format implementation plan.

High-level:

- **Base image**: fork of `anthropics/claude-code/.devcontainer` — Node 20, firewall allowlist, git, zsh, fzf
- **Per-org named volumes**: `claude-data-<org>` (at `/home/node/.claude`), `workspace-<org>`
- **Shared host bind-mounts**: `~/.claude/plugins`, `~/.claude/skills`, `settings.json`, `CLAUDE.md`, Obsidian brain vault
- **Shared CLI volume**: `claude-cli-bin` at `/opt/claude-cli` — live-upgradeable without container restart
- **Launcher**: `bin/claude-sandbox <org>` drops you into an interactive shell with the right context

## Security model

| Control | Default | Override |
|---|---|---|
| Outbound firewall | **on** — allowlist of npm, GitHub, Anthropic API, Sentry, VS Code marketplace. Uses `GH_TOKEN` if set to avoid anonymous rate limits when fetching GitHub IP ranges. Retries 3× on transient failures. | `FIREWALL=off` in `orgs/<org>/.env` |
| Extra allowed domains | none | `EXTRA_ALLOWED_DOMAINS="host1 host2"` |
| `claude` command inside container | wrapper at `/usr/local/bin/claude` always appends `--dangerously-skip-permissions` | call `/opt/claude-cli/bin/claude` for raw CLI |
| Host filesystem | no arbitrary bind-mounts; user home is **not** exposed | N/A |
| Host Claude config | `~/.claude/plugins` and `~/.claude/skills` **rw**; `settings.json` and `CLAUDE.md` **ro**; `keybindings.json` intentionally not mounted | `--no-host-mounts` disables all host bind-mounts |
| Brain vault | RW-mounted at `/brain` on all orgs | `--no-host-mounts` |
| SSH keys | `~/.ssh` **ro**-mounted so containers can `git clone`/`push` via SSH — keys are readable, not modifiable | `--no-host-mounts` |
| Credentials | per-org volume (`claude-data-<org>`); never shared | N/A |

Running `claude --dangerously-skip-permissions` is safe **only** when the firewall is on and you trust the repository you've cloned. See [Anthropic's devcontainer guidance](https://code.claude.com/docs/en/devcontainer) for context.

## Maintainer tasks

Flip the GHCR image to public (one-time, after first successful CI build):

```bash
# If gh token lacks packages scope, first run:
gh auth refresh -h github.com -s read:packages,write:packages
./bin/publish-image
```

## Roadmap

Feature tracker. Items get ticked off when shipped. File an issue to propose additions or change priority.

### Fork-safety + supply chain
- [ ] SHA256-pinned git-delta install (no silent tamper)
- [ ] Vendored zsh-in-docker install script (no remote `curl | sh`)
- [ ] Optional brain vault mount via `BRAIN_PATH` env (fork-portable)
- [ ] Fork-safe CI image tags via `${{ github.repository_owner }}`
- [ ] Fail-loud bootstrap: container exits on repo-clone failure
- [ ] All GitHub Actions pinned by commit SHA
- [ ] Base image (`node`) pinned by digest with Dependabot bumps
- [ ] `.dockerignore` + `.editorconfig` + `CONTRIBUTING.md` + `SECURITY.md`

### Versioning + release discipline
- [ ] `VERSION` file drives semver tags (`:v1`, `:v1.2`, `:v1.2.3`, `:latest`, `:sha-<sha>`)
- [ ] Breaking-change gate in CI (refuses merge without `VERSION` bump on firewall/compose/launcher edits)
- [ ] `RELEASING.md` with semver rules
- [ ] Launcher warns when local image lags upstream by a major version
- [ ] `IMAGE` env var lets consumers pin any channel

### Firewall hardening
- [ ] Multi-A record capture for CDN-fronted hosts
- [ ] Explicit IPv6 policy (default deny, `IPV6=allow` escape hatch)
- [ ] Periodic allowlist refresh (15 min default)
- [ ] Rate-limited drop log + `doctor` surfaces recent drops

### IDE integration
- [ ] Persistent container lifecycle: `up`, `stop`, `status`, `logs`
- [ ] `./bin/claude-sandbox <org> ide [code|cursor|codium]` — one-command attach
- [ ] `--repo <name>` opens directly inside a cloned subrepo
- [ ] `ide-cli` wrapper around `devcontainer up` (Zed + headless)
- [ ] JetBrains Gateway via opt-in `ENABLE_SSHD=1` (pubkey-only, localhost-bound)

### Claude Code ergonomics
- [ ] `.claude/settings.json.example` with sandbox-friendly defaults
- [ ] `.claude/CLAUDE.md.example` baseline (firewall, mounts, brain)
- [ ] MCP sidecar pattern in `compose.override.example.yml`
- [ ] README "Claude Code integration" section (mount map, RO vs RW rationale, hooks caveat)

### Testing
- [ ] Cross-org isolation regression suite (`tests/isolation.bats`)
- [ ] Firewall: multi-A, IPv6 deny, refresh idempotency, malformed CIDR
- [ ] Launcher error paths: corrupt `.env`, malformed `REPOS`, missing docker socket
- [ ] `integration.sh` two-org swap + soak-test gate
- [ ] CI runs expanded tests on PRs touching `.devcontainer/` or compose

### Compose + maintainability
- [ ] Volume mount anchors (reduce duplication across `dev`/`throwaway`/`agent`)
- [ ] `NODE_IMAGE` build arg shared between Dockerfile + `cli-init`
- [ ] Healthchecks on `dev`/`throwaway`/`agent` (`iptables allowlist` + CLI binary present)

### Docs
- [ ] README "Firewall" section explains algorithm + refresh + verification
- [ ] README "Brain vault" section documents opt-in + blast radius
- [ ] README "Upgrade policy" section (link to RELEASING.md)
- [ ] `UPSTREAM.md` — resync procedure from anthropics/claude-code/.devcontainer
- [ ] `compose.override.example.yml` worked example in README
- [ ] `docs/INDEX.md` — map of design + plan docs

## License

MIT — see [LICENSE](./LICENSE).

Credit to Anthropic for the [reference devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer) that this project extends.
