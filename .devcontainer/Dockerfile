# Forked from anthropics/claude-code/.devcontainer/Dockerfile
# See .devcontainer/UPSTREAM.md for drift log and upstream SHA.

# Base image is a build arg so docker-compose + Dockerfile stay in sync via
# a single NODE_IMAGE var. Pin to a digest (node:20-bookworm@sha256:<digest>)
# for reproducibility — run `./bin/update-base-digest` to populate the digest
# on first clone; Dependabot bumps it weekly thereafter (.github/dependabot.yml
# has a docker rule pointed at .devcontainer/).
ARG NODE_IMAGE=node:20-bookworm
FROM ${NODE_IMAGE}

ARG TZ
ENV TZ="$TZ"

# NOTE: CLAUDE_CODE_VERSION argument is intentionally removed — the CLI lives
# in a shared named volume mounted at /opt/claude-cli, not in the image.

RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG USERNAME=node

# Create shared CLI prefix dir; volume will be mounted on top of it at runtime.
RUN mkdir -p /opt/claude-cli && \
  chown -R node:node /opt/claude-cli

# Persist bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

ENV DEVCONTAINER=true

# Pre-create mount targets so volumes mount cleanly with correct ownership.
RUN mkdir -p /workspace /home/node/.claude /home/node/.claude/plugins \
  /home/node/.claude/skills /home/node/.claude/projects /brain && \
  chown -R node:node /workspace /home/node/.claude /brain

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
ARG GIT_DELTA_SHA256_AMD64=1658c7b61825d411b50734f34016101309e4b6e7f5799944cf8e4ac542cebd7f
ARG GIT_DELTA_SHA256_ARM64=937781aa7788e1510858743fff6c9a8b4a69fe0a22a7c8a69493e633227939a9
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    amd64) EXPECTED="$GIT_DELTA_SHA256_AMD64" ;; \
    arm64) EXPECTED="$GIT_DELTA_SHA256_ARM64" ;; \
    *) echo "unsupported arch for git-delta: $ARCH" >&2; exit 1 ;; \
  esac && \
  wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  echo "$EXPECTED  git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" | sha256sum -c - && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER node

# npm global prefix points to the shared volume mount.
ENV NPM_CONFIG_PREFIX=/opt/claude-cli
ENV PATH=$PATH:/opt/claude-cli/bin

ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

ARG ZSH_IN_DOCKER_VERSION=1.2.0
ARG ZSH_IN_DOCKER_SHA256=f74e5b08c295b6c3886654bb63c688e5ea16c58a4209435c4ddbab2c42fe9b41
COPY --chown=node:node zsh-in-docker.sh /tmp/zsh-in-docker.sh
RUN echo "$ZSH_IN_DOCKER_SHA256  /tmp/zsh-in-docker.sh" | sha256sum -c - && \
  sh /tmp/zsh-in-docker.sh \
    -p git \
    -p fzf \
    -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "source /usr/share/doc/fzf/examples/completion.zsh" \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    -x && \
  rm /tmp/zsh-in-docker.sh

# NOTE: Claude CLI install deliberately NOT here. See docs/superpowers/specs/
# for the live-upgrade design. Launcher populates /opt/claude-cli on first run.

# Wrapper that always passes --dangerously-skip-permissions. Sandbox is
# the isolation boundary; prompting for permission inside every time defeats
# the point. Users who need vanilla Claude can still call /opt/claude-cli/bin/claude.
USER root
RUN printf '#!/bin/bash\nexec /opt/claude-cli/bin/claude --dangerously-skip-permissions "$@"\n' > /usr/local/bin/claude && \
  chmod +x /usr/local/bin/claude
USER node

# Firewall scripts
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY init-firewall-wrapper.sh /usr/local/bin/init-firewall-wrapper.sh
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/init-firewall-wrapper.sh && \
  echo "node ALL=(root) NOPASSWD: SETENV: /usr/local/bin/init-firewall-wrapper.sh, SETENV: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
