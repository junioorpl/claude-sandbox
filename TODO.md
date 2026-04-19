# claude-sandbox — TODO

## Session bootstrap prompt injection

Today the "bootstrap" for every sandbox session is implicit: the host
`~/.claude/CLAUDE.md` bind-mount plus the sandbox block from
`.claude/CLAUDE.md.example` give Claude its session-start context. That works,
but it's coupled to a file the user has to hand-edit and it can't carry
per-org overrides.

Goal: a first-class, opt-in way to inject an initial system-prompt block
into every session the sandbox launches, per org.

### Design sketch

- New env var in `orgs/<org>/.env`, e.g. `BOOTSTRAP_PROMPT_FILE=./prompts/personal.md`.
- Launcher resolves the path (relative to the repo root or the org dir) and
  bind-mounts it read-only at `/home/node/.claude/bootstrap.md` (or similar).
- Two delivery options — pick whichever the CLI supports cleanly at the time:
  1. **Append to CLAUDE.md at entrypoint** — `cat /home/node/.claude/bootstrap.md >> /home/node/.claude/CLAUDE.md` inside a writable overlay so the host file stays untouched.
  2. **`--append-system-prompt` flag on the wrapper** — update `/usr/local/bin/claude` to read `BOOTSTRAP_PROMPT_FILE` and pass `--append-system-prompt "$(cat …)"` when present.
- Keep both the host-wide bootstrap (in `~/.claude/CLAUDE.md`) and the
  sandbox/org-specific bootstrap composable: host block first, then the org
  block, so a user's global caveman/vault prefs always win but the org can
  layer on "you are working inside acme; internal package registry is X".

### Candidate prompts worth pre-shipping

- **Caveman preload** — one-line reminder that full-intensity caveman mode
  is active (already lives in the host `CLAUDE.md`; only needed in the sandbox
  bootstrap when host mounts are disabled via `--no-host-mounts`).
- **Brain vault ingest** — if `/brain` is populated, instruct the agent to
  consult `brain/maps/MOC-index.md` and honor `brain/VAULT-RULES.md` before
  any vault writes.
- **Sandbox self-awareness** — firewall allowlist, RO/RW mount map,
  `--dangerously-skip-permissions` is already on, `/opt/claude-cli/bin/claude`
  as the raw-binary escape hatch.

### Docs / examples to add when shipped

- `prompts/bootstrap.example.md` in the repo root with the three blocks above.
- README "Bootstrap prompt" section alongside "Brain vault".
- Roadmap checkbox under "Claude Code ergonomics".



## Performance tweaks (ordered by impact on dev-loop latency on macOS)

On macOS, Docker Desktop's VirtioFS bind-mounts dominate dev-server cold-start
and HMR latency. These are the levers that actually move the needle.

### 1. Move `node_modules` off bind-mounts (biggest win)
Dependency trees via VirtioFS are 10–50× slower than a named volume for
install + TypeScript type-resolution + ESLint walks. Per project:

```yaml
# in the project's own docker-compose.yml (or overlay inside sandbox)
services:
  <app>:
    volumes:
      - <app>-node-modules:/workspace/<app>/node_modules
volumes:
  <app>-node-modules:
```

Requires `npm install` to run inside the container to populate the volume.

### 2. Turn off Vite's `usePolling`
`revendaflash/apps/web/vite.config.ts` sets `server.watch.usePolling: true`
with a 1 s interval — required today because `node_modules` is bind-mounted
and native fs events over VirtioFS are unreliable. Once node_modules moves
to a named volume (tweak 1), drop `usePolling` and HMR becomes event-driven.

### 3. Mount the workspace with `cached`
The sandbox's `workspace-<org>` is a named volume, so this only applies to
future bind-mounts added via `compose.override.yml`. Mount flag
`:cached` lets the host lead writes → faster large-file reads.

### 4. Persist pnpm/npm store as a named volume
Avoid re-downloading packages on every fresh org / throwaway container:

```yaml
services:
  dev:
    volumes:
      - npm-store:/home/node/.npm
volumes:
  npm-store:
```

### 5. Pin `NODE_IMAGE` digest in org .env
`docker-compose.yml:35` already pins the base node image by digest. Verify
each org's `.env` doesn't override it — a floating tag triggers layer
rebuilds on image pulls.

### 6. Raise Docker Desktop resources
Defaults are 4 CPU / 8 GB on macOS. For sandbox + postgres + API tsx-watch
+ Vite + TypeScript LS, bump to 6 CPU / 12 GB minimum. Settings → Resources.

### 7. Consider a Linux dev VM (UTM / OrbStack) for hot loops
If perf is still painful after 1–3, the real fix is ditching VirtioFS.
OrbStack uses a lighter VFS layer and measurably beats Docker Desktop on
node-heavy workloads. Drop-in replacement for Docker Desktop.

## Infra wiring

### Shared Postgres network (DONE — this setup)
- `/Users/euripedescabral/cabral-dev/docker-compose.yml` → top-level pg
- `claude-sandbox/compose.override.yml` → dev attaches to `cabral-dev_default`
- Requires running the top-level compose before `claude-sandbox <org>`

### Port publishing on dev container (DONE)
`compose.override.yml` publishes 4000 (API) and 5173 (web). Extend as new
apps are added; beware collisions when running multiple sandboxes.

### Still to do
- Make `revendaflash/docker-compose.yml` use the shared `cabral-dev_default`
  network too (so its containerised backend/frontend share the same pg),
  instead of spinning up a second pg.
- Document required top-level compose in `claude-sandbox/README.md`.
- Add `postgres` (and any sidecars added to top-level compose) to
  `EXTRA_ALLOWED_DOMAINS` defaults if the firewall is ever flipped to
  resolve-by-name allowlisting.
