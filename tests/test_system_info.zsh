#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

# Run via dispatcher with mocks; request JSON for deterministic ordering
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh bin/macadmin system-info --json
assert_exit0 $R_STATUS "system_info: exits 0"
assert_contains "$R_OUT" '"product_version"' "system_info: has product_version key"
assert_contains "$R_OUT" '15.6.1' "system_info: uses sw_vers mock"
