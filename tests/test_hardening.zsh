#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/hardening.zsh status
assert_exit0 $R_STATUS "hardening: status exits 0"
assert_contains "$R_OUT" "Firewall" "hardening: shows firewall"
assert_contains "$R_OUT" "Gatekeeper" "hardening: shows gatekeeper"
assert_contains "$R_OUT" "SIP" "hardening: shows sip"
assert_contains "$R_OUT" "FileVault" "hardening: shows fv"

