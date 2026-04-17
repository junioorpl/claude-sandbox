#!/usr/bin/env bats
# tests/launcher.bats — launcher arg parsing + validation (no docker required).

setup() {
  LAUNCHER="$BATS_TEST_DIRNAME/../bin/claude-sandbox"
  TMPDIR_LOCAL="$(mktemp -d)"
  export HOME="$TMPDIR_LOCAL/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$TMPDIR_LOCAL"
}

make_tmp_repo() {
  # Replicates the repo tree into a temp dir so tests don't mutate the real one.
  REPO="$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  cp -r "$REPO/bin" "$TMP/"
  cp -r "$REPO/.devcontainer" "$TMP/"
  cp "$REPO/docker-compose.yml" "$TMP/" 2>/dev/null || true
  mkdir -p "$TMP/orgs"
  echo "$TMP"
}

@test "no args -> usage exit 0" {
  run "$LAUNCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--help -> usage exit 0" {
  run "$LAUNCHER" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "usage lists new subcommands" {
  run "$LAUNCHER" --help
  [[ "$output" == *"ide"* ]]
  [[ "$output" == *"up"* ]]
  [[ "$output" == *"stop"* ]]
  [[ "$output" == *"status"* ]]
  [[ "$output" == *"logs"* ]]
  [[ "$output" == *"pull-image"* ]]
}

@test "invalid org name (uppercase) rejected" {
  run "$LAUNCHER" InvalidOrg
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid org name"* ]]
}

@test "invalid org name (special char) rejected" {
  run "$LAUNCHER" "my;org"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid org name"* ]]
}

@test "missing org .env file -> actionable error" {
  run "$LAUNCHER" nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* ]]
  [[ "$output" == *"orgs/nonexistent/.env"* ]]
}

@test "--list on empty orgs/ prints no-orgs message" {
  TMP="$(make_tmp_repo)"
  run "$TMP/bin/claude-sandbox" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no orgs configured"* ]]
  rm -rf "$TMP"
}

@test "agent service without name -> error" {
  TMP="$(make_tmp_repo)"
  mkdir -p "$TMP/orgs/acme"
  echo "GIT_USER_NAME=x" > "$TMP/orgs/acme/.env"
  echo "GIT_USER_EMAIL=x@x" >> "$TMP/orgs/acme/.env"
  if ! command -v docker >/dev/null; then skip "docker not installed"; fi
  run "$TMP/bin/claude-sandbox" acme agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"agent service requires a name"* ]]
  rm -rf "$TMP"
}

@test "doctor never echoes GH_TOKEN value" {
  export GH_TOKEN="supersecret-should-not-leak"
  if ! command -v docker >/dev/null; then skip "docker not installed"; fi
  run "$LAUNCHER" doctor
  [[ "$output" != *"supersecret-should-not-leak"* ]]
}

@test "--no-host-mounts with non-dev service errors" {
  TMP="$(make_tmp_repo)"
  mkdir -p "$TMP/orgs/acme"
  cat > "$TMP/orgs/acme/.env" <<EOF
GIT_USER_NAME=x
GIT_USER_EMAIL=x@x
EOF
  run "$TMP/bin/claude-sandbox" --no-host-mounts acme throwaway
  [ "$status" -ne 0 ]
  [[ "$output" == *"only supported for dev"* ]]
  rm -rf "$TMP"
}

@test "vscode subcommand generates per-org .devcontainer" {
  TMP="$(make_tmp_repo)"
  mkdir -p "$TMP/orgs/acme"
  echo "GIT_USER_NAME=x" > "$TMP/orgs/acme/.env"
  echo "GIT_USER_EMAIL=x@x" >> "$TMP/orgs/acme/.env"
  run bash -c "cd '$TMP' && ./bin/claude-sandbox acme vscode"
  [ "$status" -eq 0 ]
  [ -f "$TMP/.devcontainer/.generated/acme/devcontainer.json" ]
  grep -q "claude-data-acme" "$TMP/.devcontainer/.generated/acme/devcontainer.json"
  rm -rf "$TMP"
}

@test "unknown service name -> usage hint includes new subcommands" {
  TMP="$(make_tmp_repo)"
  mkdir -p "$TMP/orgs/acme"
  cat > "$TMP/orgs/acme/.env" <<EOF
GIT_USER_NAME=x
GIT_USER_EMAIL=x@x
EOF
  run "$TMP/bin/claude-sandbox" acme totally-bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown service"* ]]
  [[ "$output" == *"ide"* ]]
  rm -rf "$TMP"
}

@test "ide subcommand with unknown editor fails cleanly" {
  TMP="$(make_tmp_repo)"
  mkdir -p "$TMP/orgs/acme"
  cat > "$TMP/orgs/acme/.env" <<EOF
GIT_USER_NAME=x
GIT_USER_EMAIL=x@x
EOF
  # Minimal PATH so bash + coreutils work but no editors resolve.
  run env PATH="/usr/bin:/bin" "$TMP/bin/claude-sandbox" acme ide
  [ "$status" -ne 0 ]
  [[ "$output" == *"no supported editor"* ]]
  rm -rf "$TMP"
}

@test "ide --repo needs a value" {
  TMP="$(make_tmp_repo)"
  mkdir -p "$TMP/orgs/acme"
  cat > "$TMP/orgs/acme/.env" <<EOF
GIT_USER_NAME=x
GIT_USER_EMAIL=x@x
EOF
  run "$TMP/bin/claude-sandbox" acme ide --repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a value"* ]]
  rm -rf "$TMP"
}

@test "BRAIN_PATH unset does not leak personal path warnings" {
  # Regression: pre-BRAIN_PATH launcher warned "brain vault not found at cabral-dev/brain"
  TMP="$(make_tmp_repo)"
  mkdir -p "$TMP/orgs/acme"
  cat > "$TMP/orgs/acme/.env" <<EOF
GIT_USER_NAME=x
GIT_USER_EMAIL=x@x
EOF
  if ! command -v docker >/dev/null; then skip "docker not installed"; fi
  run env HOME="$HOME" "$TMP/bin/claude-sandbox" acme doctor
  [[ "$output" != *"cabral-dev"* ]]
  rm -rf "$TMP"
}
