# Forked from anthropics/claude-code/.devcontainer/Dockerfile
# See .devcontainer/UPSTREAM.md for drift log and upstream SHA.

FROM node:20

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
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER node

# npm global prefix points to the shared volume mount.
ENV NPM_CONFIG_PREFIX=/opt/claude-cli
ENV PATH=$PATH:/opt/claude-cli/bin

ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# NOTE: Claude CLI install deliberately NOT here. See docs/superpowers/specs/
# for the live-upgrade design. Launcher populates /opt/claude-cli on first run.

# Firewall scripts
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY init-firewall-wrapper.sh /usr/local/bin/init-firewall-wrapper.sh
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/init-firewall-wrapper.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall-wrapper.sh, /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
