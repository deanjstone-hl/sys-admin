#!/usr/bin/env bats
# Confirms the bats scaffold itself is wired up correctly.
# Per deanjstone/sys-admin#15, substantive script coverage lands in #20 —
# this file and the per-script smoke tests alongside it just prove the
# framework runs, not that the scripts are fully covered.

@test "bats runs and reports success" {
  run true
  [ "$status" -eq 0 ]
}

@test "bats reports failure correctly" {
  run false
  [ "$status" -ne 0 ]
}
