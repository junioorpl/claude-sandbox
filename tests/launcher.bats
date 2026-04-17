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
  REPO="$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  cp -r "$REPO/bin" "$TMP/"
  mkdir "$TMP/orgs"
  run "$TMP/bin/claude-sandbox" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no orgs configured"* ]]
  rm -rf "$TMP"
}

@test "agent service without name -> error" {
  REPO="$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  cp -r "$REPO/bin" "$TMP/"
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
  REPO="$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  cp -r "$REPO/bin" "$TMP/"
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
  REPO="$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  cp -r "$REPO/bin" "$TMP/"
  cp -r "$REPO/.devcontainer" "$TMP/"
  mkdir -p "$TMP/orgs/acme"
  echo "GIT_USER_NAME=x" > "$TMP/orgs/acme/.env"
  echo "GIT_USER_EMAIL=x@x" >> "$TMP/orgs/acme/.env"
  run bash -c "cd '$TMP' && ./bin/claude-sandbox acme vscode"
  [ "$status" -eq 0 ]
  [ -f "$TMP/.devcontainer/.generated/acme/devcontainer.json" ]
  grep -q "claude-data-acme" "$TMP/.devcontainer/.generated/acme/devcontainer.json"
  rm -rf "$TMP"
}
