# Security Policy

## Supported versions

| Version channel | Supported |
|---|---|
| `:latest` | ✅ critical + high fixes |
| `:v<major>` (e.g., `:v1`) | ✅ critical + high fixes for the latest major |
| `:v<major>.<minor>` (e.g., `:v1.2`) | ✅ critical fixes only |
| `:v<major>.<minor>.<patch>` (pinned exact) | ❌ no backport; upgrade to the next minor |
| Older majors | ❌ unsupported; upgrade |

## Reporting a vulnerability

Please **do not** open a public issue for security reports.

Use GitHub's private vulnerability reporting: [Report a vulnerability](https://github.com/junioorpl/claude-sandbox/security/advisories/new).

We acknowledge reports within **72 hours** and aim to fix-or-explain within **14 days** for critical and high-severity findings.

## Scope

In scope:

- **Supply chain**: unverified downloads in `.devcontainer/Dockerfile`, image base drift, registry hijack surface.
- **Firewall bypasses**: ways to reach hosts outside the allowlist with `FIREWALL=on`.
- **Privilege escalation**: paths from `node` user to `root` inside the container, or from container to host.
- **Cross-org leakage**: any way one org's container can read another org's credentials, workspace, or env.
- **Launcher injection**: command injection via org names, REPOS values, or `.env` contents.
- **Secret exposure**: credentials or tokens visible in logs, `docker inspect`, or `docker compose config` output.

Out of scope:

- Host-level Docker configuration choices (user namespaces, rootless mode).
- Vulnerabilities in dependencies that have a published fix — please upgrade.
- Missing hardening that is already tracked in the public roadmap.
- The `--dangerously-skip-permissions` flag itself — it is the *point* of the sandbox.
- Opt-in features (`FIREWALL=off`, `ENABLE_SSHD=1`) — documented trade-offs.

## Coordinated disclosure

If the issue affects upstream (`anthropics/claude-code/.devcontainer`), we will coordinate with Anthropic's security team before public disclosure.

We prefer coordinated disclosure with a 90-day window from first report. If we can't fix within that window, we'll explain why and agree a revised timeline with the reporter.
