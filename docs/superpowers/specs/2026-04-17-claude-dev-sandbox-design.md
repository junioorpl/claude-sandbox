---
date: 2026-04-17
tags: [decision, infrastructure, claude-code, devcontainer]
related: []
---

# Claude Dev Sandbox — Design

## Goal

A portable, per-organization isolated environment for running Claude Code with `--dangerously-skip-permissions`. Replicable across machines; zero cross-org credential or filesystem contamination.

## Non-Goals

- Bind-mounting arbitrary host project directories (code is cloned inside the container)
- Cloud/remote execution (local Docker only)
- Support for non-Node toolchains on day one (Python/Go can be added per-org later)

Two narrowly-scoped host bind-mounts are intentional exceptions (see Host Integration Mounts): Claude plugin/settings dirs, and the Obsidian brain vault.

## Approach

Fork Anthropic's reference devcontainer (`anthropics/claude-code/.devcontainer`) and wrap it with a per-org launcher + compose layer. Upstream provides the hardened base (firewall, Node 20, Claude CLI); our additions provide portability and multi-org isolation.

### Why not alternatives

| Considered | Rejected because |
|---|---|
| Docker Sandboxes (Docker Desktop 4.50+) | Ties setup to Docker Desktop; less transparent for customization |
| textcortex/claude-code-sandbox | Archived upstream; uncertain future |
| Fully custom Dockerfile | Duplicates work already done and maintained by Anthropic |

## Architecture

```
claude-sandbox/                         # git repo, public or private
├── .devcontainer/
│   ├── devcontainer.json               # forked from upstream; mounts parameterized by ORG
│   ├── Dockerfile                      # forked; Node 20 + git + zsh + fzf (CLI in shared volume)
│   └── init-firewall.sh                # forked; iptables allowlist, toggleable
├── docker-compose.yml                  # compose-based launch, equivalent to devcontainer
├── bin/
│   └── claude-sandbox                  # launcher wrapper around docker compose
├── orgs/
│   ├── .gitkeep
│   └── <org>/.env                      # user-created per org (gitignored)
├── .env.example
├── .gitignore                          # ignores orgs/*/.env
└── README.md
```

### Container image

- Base: fork of `anthropics/claude-code/.devcontainer/Dockerfile`
- Runtime: Node 20 LTS on Debian slim
- Preinstalled: `git`, `zsh`, `fzf`
- **Not** preinstalled: `@anthropic-ai/claude-code` — lives in a shared volume (see Live CLI Updates)
- User: `node` (non-root), home `/home/node`, workdir `/workspace`
- `PATH` includes `/opt/claude-cli/bin` so `claude` resolves to the volume-mounted binary

### Per-organization isolation

Isolation is enforced through per-org named Docker volumes for anything that carries credentials, session state, or work product. Plugins, skills, and settings are shared across orgs via host bind-mounts so that Claude behaves identically on every container.

**Per-org volumes** (named `*-<ORG>`, only the matching org can mount them):

| Volume | Mount | Purpose |
|---|---|---|
| `claude-creds-<ORG>` | `/home/node/.claude/.credentials.json`, `/home/node/.claude/statsig`, `/home/node/.claude/todos` | Login tokens, session telemetry, per-org ephemeral state |
| `claude-projects-<ORG>` | `/home/node/.claude/projects` | Per-project history, memory, transcripts |
| `workspace-<ORG>` | `/workspace` | Cloned repos, build artifacts, persistent work |

**Shared host bind-mounts** (identical across all orgs — see Host Integration Mounts below):

| Host path | Container path | Mode | Purpose |
|---|---|---|---|
| `~/.claude/plugins` | `/home/node/.claude/plugins` | rw | Plugin install state (changes propagate both ways) |
| `~/.claude/skills` | `/home/node/.claude/skills` | rw | User-authored skills |
| `~/.claude/settings.json` | `/home/node/.claude/settings.json` | ro | Global settings |
| `~/.claude/keybindings.json` | `/home/node/.claude/keybindings.json` | ro | Keybindings (if present) |
| `~/.claude/CLAUDE.md` | `/home/node/.claude/CLAUDE.md` | ro | Global user instructions |
| `~/cabral-dev/brain` | `/brain` | rw | Obsidian vault for auto-save per CLAUDE.md rules |

Org name is validated as `[a-z0-9-]+`. A container started with `ORG=acme` only mounts `*-acme` volumes; a different org's credentials and projects are unreachable from that container.

Repositories are cloned inside the container via `git clone`; host project directories are not mounted.

### Live CLI Updates (no restart required)

The Claude CLI is installed into a shared named volume, not baked into the image. Running containers pick up upgrades on the next `claude` invocation — no rebuild, no container restart.

| Volume | Mount | Mode | Purpose |
|---|---|---|---|
| `claude-cli-bin` | `/opt/claude-cli` | rw, shared across all orgs | npm prefix for `@anthropic-ai/claude-code` (contains `bin/claude`, `lib/node_modules/...`) |

Because `@anthropic-ai/claude-code` is pure JavaScript, the same install works across every container regardless of when it was started. `PATH` resolves `claude` each invocation → a new process sees the current installed version immediately.

**Flows**:

- **First launch ever** — launcher detects empty `claude-cli-bin`, runs a one-shot init container: `npm install -g --prefix /opt/claude-cli @anthropic-ai/claude-code@latest`. Subsequent launches skip this.
- **Upgrade** — `claude-sandbox upgrade` runs the same install command with `@latest` (or a pinned version) inside a disposable container writing to the shared volume. All running containers immediately see the new version on next `claude` invocation.
- **Plugin install/upgrade** — already flows through `~/.claude/plugins` host bind-mount. No container action needed; the host filesystem is the source of truth.
- **Image rebuild** — only required for changes to base OS packages, Node version, or firewall script. CLI and plugin upgrades never require it.

**Pinning**: `orgs/<name>/.env` may set `CLAUDE_CLI_VERSION=x.y.z`. If set, `claude-sandbox upgrade` pins to that version for that org's next upgrade call. Default is `latest`.

### Host Integration Mounts

Two narrowly-scoped host bind-mounts exist to make the container behave like the user's normal local environment:

1. **Claude plugin/skill/settings share** — host `~/.claude` is NOT mounted wholesale. Only the subpaths listed above are mounted individually. Credentials and per-project state live on the per-org volumes mounted at sibling subpaths, never on the host. Consequence: installing a plugin inside any container (or on the host) makes it available everywhere, while a login inside one org stays in that org.

2. **Brain vault** — `~/cabral-dev/brain` mounted RW at `/brain`. Shared across all orgs. Claude follows the auto-save rules from global `CLAUDE.md` (decisions, solutions, learnings, daily log, job-search notes) from inside any container, writing directly to the host vault.

Both mounts are declared as the same compose block and enabled for every service. A user who wants a hermetic run (no host bleed-through) can pass `--no-host-mounts` to the launcher, which omits this block.

### Network

- Default: upstream firewall (`init-firewall.sh`) active → allowlist of npm registry, GitHub, Claude API, DNS, SSH.
- Per-org override: `orgs/<name>/.env` may set `FIREWALL=off` to disable the firewall and allow full outbound internet. Off by default → must be opted into explicitly per org.
- No inbound ports published to host.

### Per-org env file (`orgs/<name>/.env`)

```dotenv
# Required
GIT_USER_NAME="Eurípedes Cabral"
GIT_USER_EMAIL="work-email@acme.com"

# Optional
GH_TOKEN=                    # GitHub token for gh CLI / private repos
FIREWALL=on                  # on (default) | off
EXTRA_ALLOWED_DOMAINS=       # space-separated, appended to firewall allowlist
```

The launcher loads this file before invoking docker compose. Git identity is applied inside the container on first shell spawn.

### Launcher (`bin/claude-sandbox`)

```
claude-sandbox <org>                    # interactive shell, persistent workspace
claude-sandbox <org> throwaway          # --rm + anonymous workspace volume
claude-sandbox <org> agent <name>       # named parallel instance, own workspace
claude-sandbox --list                   # list configured orgs (from orgs/*/)
claude-sandbox --build                  # rebuild local image
claude-sandbox upgrade [version]        # upgrade shared Claude CLI volume
claude-sandbox doctor                   # diagnose: image, volumes, mounts, CLI version
```

Responsibilities:
1. Validate `orgs/<org>/.env` exists (unless `--list`/`--build`/`upgrade`/`doctor`)
2. Export `ORG=<org>` and source the org env file
3. Ensure `claude-cli-bin` volume is populated (run init container if empty)
4. Invoke `docker compose run --rm -e ORG=... <service>`
5. Drop user into `/workspace` shell; `claude --dangerously-skip-permissions` is the suggested next command (not auto-run, so user can clone first)

### Compose services (`docker-compose.yml`)

| Service | Behavior |
|---|---|
| `dev` | Persistent workspace volume, interactive shell. Default. |
| `throwaway` | `--rm`, anonymous workspace, no persistence between runs. |
| `agent` | Template for parallel runs; accepts `AGENT_NAME` to derive a distinct workspace volume (`workspace-<ORG>-<AGENT_NAME>`). Auth + config volumes still shared with org. |

All services share the same image and the same `claude-creds-<ORG>` / `claude-projects-<ORG>` / `claude-cli-bin` volumes, plus the host bind-mounts listed in Host Integration Mounts.

### Distribution

- **Source**: `github.com/euripedescabral/claude-sandbox` (public or private repo)
- **Prebuilt image**: `ghcr.io/euripedescabral/claude-sandbox:latest`, tagged per Node LTS + commit SHA. Built by GitHub Actions on push to `main`.
- **Compose default**: pulls from GHCR; `--build` flag forces local build

### New-machine setup

```bash
git clone git@github.com:euripedescabral/claude-sandbox.git ~/claude-sandbox
cd ~/claude-sandbox
cp .env.example orgs/personal/.env && $EDITOR orgs/personal/.env
./bin/claude-sandbox personal
# inside container:
git clone <repo>
cd <repo>
claude --dangerously-skip-permissions
```

## Data Flow

1. Launcher reads `orgs/<org>/.env`, exports vars
2. `docker compose run` pulls image, creates/mounts org-specific volumes
3. Container boots → `init-firewall.sh` runs (if `FIREWALL=on`)
4. User lands in `/workspace` as `node` user
5. `git clone` → `cd repo` → `claude --dangerously-skip-permissions`
6. Claude operates inside `/workspace`, can read/write only that volume
7. `git push` to remote completes the round-trip; nothing touches host

## Error Handling

- Missing `orgs/<org>/.env` → launcher exits with usage hint
- Docker daemon not running → launcher exits with actionable message
- Firewall init failure when `FIREWALL=on` → container refuses to start (fail-closed). When `FIREWALL=off`, `init-firewall.sh` is skipped entirely.
- Volume conflicts (e.g., `ORG` name with unsafe chars) → launcher validates `[a-z0-9-]+` and rejects

## Testing Strategy

- **Unit**: launcher script tested with `bats` — arg parsing, env loading, validation
- **Integration**: smoke-test compose services build and run; `claude --version` inside container succeeds
- **Isolation test**: start two orgs, verify one cannot see the other's `~/.claude` or `/workspace` contents
- **Firewall test**: verify allowlist blocks an unlisted domain (e.g., `curl example.com` fails with `FIREWALL=on`, succeeds with `FIREWALL=off`)

## Open Questions

- **VS Code devcontainer org parameterization.** `devcontainer.json` has no native env-var interpolation for mount sources. Options to resolve at implementation: (a) generate a per-org `.devcontainer/devcontainer.json` from a template when the user runs `claude-sandbox <org> vscode`, (b) keep VS Code flow limited to a single default org and require the CLI launcher for multi-org, or (c) use devcontainer `initializeCommand` to symlink the active org's compose override before VS Code builds. Pick during implementation; does not affect the non-VS-Code CLI flow.

## Trade-offs Accepted

- **Volume-only isolation** (not separate networks or images) keeps setup simple at the cost of not isolating network namespaces per org. Mitigated by the firewall.
- **Per-org credentials, shared plugins/skills/settings** — plugins and settings propagate everywhere via host bind-mount; credentials and project state stay per-org in volumes. User explicitly chose this split over stricter full-isolation.
- **Git clone inside container** (vs. bind-mount) means host editor tools (VS Code on host) cannot directly edit code — user must either use the devcontainer VS Code flow or work inside the container shell. Accepted to guarantee host project files are untouched.
- **Shared Claude CLI volume** (vs. per-image install) enables no-restart upgrades at the cost of a volume that must be initialized once. Acceptable: init is one-shot and idempotent.
- **Brain vault RW bind-mount** — any container can write to the user's knowledge vault. Accepted because auto-save is an explicit requirement from global CLAUDE.md; the alternative (per-org brain copies) breaks the single-source-of-truth model.
