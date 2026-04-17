#!/usr/bin/env bats
# tests/firewall.bats — verifies init-firewall-wrapper.sh honors FIREWALL env
# and that init-firewall.sh static analysis holds. Most behavioral coverage
# lives in tests/integration.sh (requires docker).

setup() {
  WRAPPER="$BATS_TEST_DIRNAME/../.devcontainer/init-firewall-wrapper.sh"
  FIREWALL_SCRIPT="$BATS_TEST_DIRNAME/../.devcontainer/init-firewall.sh"
}

@test "FIREWALL=off skips inner script and exits 0" {
  run env FIREWALL=off bash "$WRAPPER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Disabled via FIREWALL=off"* ]]
}

@test "FIREWALL=invalid exits non-zero with error message" {
  run env FIREWALL=bogus bash "$WRAPPER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid FIREWALL value"* ]]
}

@test "FIREWALL unset attempts to run inner script" {
  # Defaults to "on" and calls init-firewall.sh, which bails without iptables.
  # We only assert it did NOT hit the disabled/invalid paths.
  run env -u FIREWALL bash "$WRAPPER"
  [[ "$output" != *"Disabled via FIREWALL=off"* ]]
  [[ "$output" != *"invalid FIREWALL value"* ]]
}

@test "init-firewall.sh has IPv6 policy block" {
  grep -q 'ip6tables' "$FIREWALL_SCRIPT"
  grep -q 'IPV6_MODE' "$FIREWALL_SCRIPT"
}

@test "init-firewall.sh resolve_and_add handles multiple A records" {
  # resolve_and_add iterates over every A record; not just the first.
  grep -q 'while IFS= read -r ip' "$FIREWALL_SCRIPT"
  grep -q 'ipset add allowed-domains .* -exist' "$FIREWALL_SCRIPT"
}

@test "init-firewall.sh supports refresh mode" {
  grep -q 'FIREWALL_REFRESH' "$FIREWALL_SCRIPT"
  grep -q 'REFRESH_MODE' "$FIREWALL_SCRIPT"
}

@test "init-firewall.sh emits rate-limited drop log" {
  grep -q 'fw-drop:' "$FIREWALL_SCRIPT"
  grep -q -- '--limit 5/min' "$FIREWALL_SCRIPT"
}

@test "init-firewall-wrapper.sh backgrounds refresh loop" {
  grep -q 'FIREWALL_REFRESH=1' "$WRAPPER"
  grep -q 'REFRESH_INTERVAL' "$WRAPPER"
}

@test "init-firewall.sh accepts newline-delimited EXTRA_ALLOWED_DOMAINS" {
  grep -q "tr ' ' '\\\\n'" "$FIREWALL_SCRIPT"
}

@test "init-firewall.sh validates CIDR from GitHub meta" {
  grep -q 'Invalid CIDR range from GitHub meta' "$FIREWALL_SCRIPT"
}
