# claude-sandbox

Portable, per-organization isolated Docker environment for running [Claude Code](https://github.com/anthropics/claude-code) with `--dangerously-skip-permissions` safely.

Fork of Anthropic's reference devcontainer, wrapped with a per-org launcher, Docker Compose services, and a shared Claude CLI volume that supports hot upgrades without rebuilding images or restarting containers.

## Why

- **`--dangerously-skip-permissions` without risk** — container isolation + firewall allowlist
- **Per-organization isolation** — separate volumes for credentials, projects, and workspace; zero cross-org contamination
- **Shared plugins and settings** — your host `~/.claude/plugins`, `skills`, and `settings.json` propagate into every container
- **Hot CLI upgrades** — `claude-sandbox upgrade` bumps the Claude CLI in a shared volume; running containers pick it up on next invocation
- **One-command IDE open** — `claude-sandbox <org> ide` attaches VS Code or Cursor to a live container in under 3 seconds once warm
- **Shareable across machines** — clone the repo, pull the prebuilt image from GHCR, drop in a per-org `.env`, and you're running in under a minute

## Quick start

1. **Prerequisites**: Docker Desktop 4.30+ (or Docker Engine 24+) with `docker compose`.

2. **Clone + interactive setup**:

   ```bash
   git clone git@github.com:junioorpl/claude-sandbox.git ~/claude-sandbox
   cd ~/claude-sandbox
   ./bin/setup          # prompts for org name, git identity, optional shell alias
   ```

   After the alias lands (`source ~/.zshrc` or new terminal), `claude-sandbox <org>` works from anywhere. Install standalone via `./bin/install-alias`.

3. **Open in your editor (one command)**:

   ```bash
   claude-sandbox personal ide            # auto-detects cursor → code → codium
   claude-sandbox personal ide cursor     # force Cursor
   claude-sandbox personal ide --repo myrepo   # open inside /workspace/myrepo
   ```

   The container launches if not already running, and your editor attaches to `/workspace` via the standard `vscode-remote://attached-container+…` URI — works for VS Code, Cursor, and Codium out of the box.

4. **Or open a terminal-only session**:

   ```bash
   claude-sandbox personal                # ephemeral shell, persistent /workspace
   ```

5. **Inside the container**:

   ```bash
   git clone git@github.com:you/your-repo.git
   cd your-repo
   claude                   # already runs with --dangerously-skip-permissions
   ```

   The sandbox **is** the isolation boundary, so `claude` inside any container is a wrapper that always passes `--dangerously-skip-permissions`. Call `/opt/claude-cli/bin/claude` if you ever need the raw CLI.

## Common tasks

```bash
# Org management
./bin/claude-sandbox --list                   # list configured orgs
./bin/claude-sandbox <org> up                 # start persistent container (backgrounded)
./bin/claude-sandbox <org> attach             # shell into running container
./bin/claude-sandbox <org> status             # show container + volume state
./bin/claude-sandbox <org> logs               # stream container logs
./bin/claude-sandbox <org> stop               # stop persistent container

# Ephemeral / specialized
./bin/claude-sandbox <org> throwaway          # --rm + anonymous workspace
./bin/claude-sandbox <org> agent worker-1     # parallel named instance
./bin/claude-sandbox --no-host-mounts <org>   # hermetic run — no host bleed-through

# IDE
./bin/claude-sandbox <org> ide [editor]       # VS Code / Cursor / Codium attach
./bin/claude-sandbox <org> ide-cli            # Zed / headless via devcontainer CLI
./bin/claude-sandbox <org> vscode             # generate per-org .devcontainer/

# Image + CLI
./bin/claude-sandbox pull-image               # pull latest image for configured IMAGE
./bin/claude-sandbox upgrade                  # bump Claude CLI to latest (no restart)
./bin/claude-sandbox upgrade 1.2.3            # pin CLI to a version
./bin/claude-sandbox --build                  # rebuild local image

# Diagnostics
./bin/claude-sandbox doctor                   # image, volumes, CLI version, recent firewall drops
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
# newline-delimited (preferred) or space-separated
REPOS="git@github.com:you/repo-a.git
git@github.com:you/repo-b.git"
```

Clones are idempotent — existing dirs are skipped on subsequent launches. Container exits non-zero on the **first** clone failure, so typos surface immediately instead of quietly skipping. SSH URLs require the default `~/.ssh` bind-mount.

## Claude Code integration

Mount map inside the container:

| Path | Mode | Source | Purpose |
|---|---|---|---|
| `/workspace` | rw | per-org volume `workspace-<org>` | code lives here |
| `/home/node/.claude` | rw | per-org volume `claude-data-<org>` | credentials, projects, local state |
| `/opt/claude-cli` | rw | shared volume `claude-cli-bin` | Claude CLI binary (live-upgradeable) |
| `/home/node/.claude/plugins` | rw | host `~/.claude/plugins` | plugins propagate host ↔ container |
| `/home/node/.claude/skills` | rw | host `~/.claude/skills` | skills propagate |
| `/home/node/.claude/settings.json` | **ro** | host file | policy config; container cannot self-escalate |
| `/home/node/.claude/CLAUDE.md` | **ro** | host file | global instructions |
| `/home/node/.ssh` | **ro** | host `~/.ssh` | keys readable for git, not modifiable |
| `/brain` | rw | `$BRAIN_PATH` (opt-in) | knowledge vault (empty if unset) |

Two examples live in the repo to jumpstart your config:

- [`.claude/settings.json.example`](./.claude/settings.json.example) — sandbox-friendly defaults
- [`.claude/CLAUDE.md.example`](./.claude/CLAUDE.md.example) — a block to paste into your host `CLAUDE.md` so the model knows it's running sandboxed

**Hooks caveat**: `~/.claude/hooks` is **not** mounted. Host-side hooks don't apply inside the container. Put sandbox-side hooks in your `CLAUDE.md` or a skill.

## Brain vault (optional)

If you keep a knowledge directory on the host (Obsidian vault, notes folder), point the sandbox at it:

```dotenv
# in orgs/<org>/.env
BRAIN_PATH=$HOME/notes
```

It mounts at `/brain` read-write. Leave `BRAIN_PATH` unset and the launcher mounts an empty scratch dir at `~/.claude-sandbox/empty-brain` so the `/brain` path always exists without requiring a personal path in the shared config.

**Blast radius**: `/brain` is rw, so a malicious prompt could mutate vault content. Only enable in sandboxes you trust, and use `git` inside the vault for undo.

## Firewall

Fail-closed, allowlist-based outbound filtering driven by [`init-firewall.sh`](.devcontainer/init-firewall.sh).

**Baseline allowlist**:
- GitHub (via [`api.github.com/meta`](https://api.github.com/meta): `web`, `api`, `git` CIDRs)
- `registry.npmjs.org`
- `api.anthropic.com`
- `sentry.io`, `statsig.anthropic.com`, `statsig.com`
- `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`, `update.code.visualstudio.com`

Every other outbound connection is rejected with `icmp-admin-prohibited` and logged (rate-limited to 5/min with `fw-drop: ` prefix). Verification runs at init: must fail to reach `example.com`, must succeed to reach `api.github.com/zen`.

**Extensions**: newline- or space-separated domains in `orgs/<org>/.env`:
```dotenv
EXTRA_ALLOWED_DOMAINS="registry.internal.acme.com
packages.acme.com"
```

**Multi-A + refresh**: `resolve_and_add()` captures every A record returned, and a background loop re-resolves every `FIREWALL_REFRESH_INTERVAL` seconds (default 900). CDN-fronted hosts stay reachable as their IPs rotate.

**IPv6**: denied by default via `ip6tables -P … DROP`. Set `IPV6=allow` in the org's `.env` to opt in.

**GitHub rate limits**: set `GH_TOKEN` in the org's `.env` so the allowlist fetch uses a bearer. Anonymous fetches retry 3× with exponential backoff.

**Drop diagnostics**: `./bin/claude-sandbox <org> doctor` surfaces recent `fw-drop:` lines from `dmesg`.

## Upgrade policy

Image tags follow semver. Consumers pick a channel in `orgs/<org>/.env`:

```dotenv
IMAGE=ghcr.io/junioorpl/claude-sandbox:v1         # major channel (auto minor+patch)
# IMAGE=ghcr.io/junioorpl/claude-sandbox:v1.2     # minor channel (patches only)
# IMAGE=ghcr.io/junioorpl/claude-sandbox:v1.2.3   # exact (immutable)
# IMAGE=ghcr.io/junioorpl/claude-sandbox:latest   # always-latest (any version)
```

See [`RELEASING.md`](./RELEASING.md) for the full semver rules and rollback flow. `doctor` reports which channel your local image is tracking.

## Architecture

See [`docs/INDEX.md`](./docs/INDEX.md) for the full design + plan documentation.

High-level:

- **Base image**: fork of `anthropics/claude-code/.devcontainer` — Node 20, firewall allowlist, git, zsh, fzf (forks: drift log in [`.devcontainer/UPSTREAM.md`](./.devcontainer/UPSTREAM.md))
- **Per-org named volumes**: `claude-data-<org>` (at `/home/node/.claude`), `workspace-<org>`
- **Shared host bind-mounts**: `~/.claude/plugins`, `~/.claude/skills`, `settings.json`, `CLAUDE.md`; optional `/brain`
- **Shared CLI volume**: `claude-cli-bin` at `/opt/claude-cli` — live-upgradeable without container restart
- **Launcher**: `bin/claude-sandbox <org>` drops you into an interactive shell or attaches your IDE with the right context

## Local tweaks — `compose.override.yml`

For settings that shouldn't live in the shared config, copy the example:

```bash
cp compose.override.example.yml compose.override.yml
$EDITOR compose.override.yml
```

Docker Compose reads `compose.override.yml` automatically on every launch. The example shows patterns for: extra mounts, MCP sidecars, tighter firewall refresh intervals, and explicit IPv6 opt-in. The override file is gitignored so it stays personal.

## Security model

| Control | Default | Override |
|---|---|---|
| Outbound firewall | **on** — allowlist (GitHub, npm, Anthropic API, Sentry, VS Code marketplace); multi-A capture; 15-min refresh; IPv6 deny; rate-limited drop log | `FIREWALL=off`, `EXTRA_ALLOWED_DOMAINS=…`, `IPV6=allow` in `orgs/<org>/.env` |
| `claude` command inside container | wrapper at `/usr/local/bin/claude` always appends `--dangerously-skip-permissions` | call `/opt/claude-cli/bin/claude` for raw CLI |
| Host filesystem | no arbitrary bind-mounts; user home is **not** exposed | N/A |
| Host Claude config | `~/.claude/plugins` and `~/.claude/skills` **rw**; `settings.json` and `CLAUDE.md` **ro**; `hooks/` and `keybindings.json` intentionally not mounted | `--no-host-mounts` disables all host bind-mounts |
| Brain vault | only mounted when `BRAIN_PATH` is set; scratch dir otherwise | `--no-host-mounts` |
| SSH keys | `~/.ssh` **ro**-mounted so containers can `git clone`/`push` via SSH — keys are readable, not modifiable | `--no-host-mounts` |
| Credentials | per-org volume (`claude-data-<org>`); never shared | N/A |
| Image supply chain | git-delta + zsh-in-docker SHA256-verified; GH Actions SHA-pinned; Dependabot bumps weekly | — |

Running `claude --dangerously-skip-permissions` is safe **only** when the firewall is on and you trust the repository you've cloned. See [Anthropic's devcontainer guidance](https://code.claude.com/docs/en/devcontainer) for context. Report vulnerabilities privately via [`SECURITY.md`](./SECURITY.md).

## Maintainer tasks

Flip the GHCR image to public (one-time, after first successful CI build):

```bash
# If gh token lacks packages scope, first run:
gh auth refresh -h github.com -s read:packages,write:packages
./bin/publish-image
```

Release flow: see [`RELEASING.md`](./RELEASING.md). Upstream resync: see [`.devcontainer/UPSTREAM.md`](./.devcontainer/UPSTREAM.md).

## Roadmap

Feature tracker. Items get ticked off when shipped. File an issue to propose additions or change priority.

### Fork-safety + supply chain
- [x] SHA256-pinned git-delta install (no silent tamper)
- [x] Vendored zsh-in-docker install script (no remote `curl | sh`)
- [x] Optional brain vault mount via `BRAIN_PATH` env (fork-portable)
- [x] Fork-safe CI image tags via `${{ github.repository_owner }}`
- [x] Fail-loud bootstrap: container exits on repo-clone failure
- [x] All GitHub Actions pinned by commit SHA
- [x] `.dockerignore` + `.editorconfig` + `CONTRIBUTING.md` + `SECURITY.md`
- [ ] Base image (`node`) pinned by digest with Dependabot bumps (Dependabot will open the first PR)

### Versioning + release discipline
- [x] `VERSION` file drives semver tags (`:v1`, `:v1.2`, `:v1.2.3`, `:latest`, `:sha-<sha>`)
- [x] Breaking-change gate in CI (refuses merge without `VERSION` bump on firewall/compose/launcher edits)
- [x] `RELEASING.md` with semver rules
- [x] `IMAGE` env var lets consumers pin any channel
- [x] `doctor` reports which channel the local image is tracking
- [ ] Launcher warns when local image lags upstream by a major version

### Firewall hardening
- [x] Multi-A record capture for CDN-fronted hosts
- [x] Explicit IPv6 policy (default deny, `IPV6=allow` escape hatch)
- [x] Periodic allowlist refresh (15 min default)
- [x] Rate-limited drop log + `doctor` surfaces recent drops

### IDE integration
- [x] Persistent container lifecycle: `up`, `stop`, `status`, `logs`, `attach`
- [x] `./bin/claude-sandbox <org> ide [code|cursor|codium]` — one-command attach
- [x] `--repo <name>` opens directly inside a cloned subrepo
- [x] `ide-cli` wrapper around `devcontainer up` (Zed + headless)

### Claude Code ergonomics
- [x] `.claude/settings.json.example` with sandbox-friendly defaults
- [x] `.claude/CLAUDE.md.example` baseline (firewall, mounts, brain)
- [x] MCP sidecar pattern in `compose.override.example.yml`
- [x] README "Claude Code integration" section (mount map, RO vs RW rationale, hooks caveat)

### Testing
- [x] Firewall: multi-A, IPv6 deny, refresh idempotency, malformed CIDR (bats static + integration)
- [x] Launcher error paths: unknown service, invalid org, `ide --repo` arg validation
- [x] `integration.sh` IPv6 deny check + REPOS fail-loud check + two-volume cross-org isolation
- [ ] CI runs integration.sh on PRs touching `.devcontainer/` or compose (currently runs bats only)

### Compose + maintainability
- [x] `NODE_IMAGE` build arg shared between Dockerfile + `cli-init`
- [x] Healthcheck on dev service (CLI binary present)
- [ ] Volume mount anchors (Compose YAML merge rules limit how cleanly this works — deferred)

### Docs
- [x] README "Firewall" section explains algorithm + refresh + verification
- [x] README "Brain vault" section documents opt-in + blast radius
- [x] README "Upgrade policy" section (link to RELEASING.md)
- [x] `UPSTREAM.md` — resync procedure from anthropics/claude-code/.devcontainer
- [x] `compose.override.example.yml` worked example in README
- [x] `docs/INDEX.md` — map of design + plan docs

## License

MIT — see [LICENSE](./LICENSE).

Credit to Anthropic for the [reference devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer) that this project extends.
