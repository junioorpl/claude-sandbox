#!/usr/bin/env bats
# tests/firewall.bats — verifies init-firewall-wrapper.sh honors FIREWALL env.

setup() {
  WRAPPER="$BATS_TEST_DIRNAME/../.devcontainer/init-firewall-wrapper.sh"
}

@test "FIREWALL=off skips inner script and exits 0" {
  run env FIREWALL=off bash "$WRAPPER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Disabled via FIREWALL=off"* ]]
}

@test "FIREWALL=on exec's inner script (mocked path)" {
  skip "covered by Phase 7 integration test (requires real container)"
}

@test "FIREWALL=invalid exits non-zero with error message" {
  run env FIREWALL=bogus bash "$WRAPPER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid FIREWALL value"* ]]
}

@test "FIREWALL unset defaults to on (attempts inner script)" {
  run env -u FIREWALL bash "$WRAPPER"
  [[ "$output" != *"Disabled via FIREWALL=off"* ]]
}
