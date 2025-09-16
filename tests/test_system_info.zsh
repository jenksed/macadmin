#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

# Run with mocks to keep fast and deterministic
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/system_info.zsh
assert_exit0 $R_STATUS "system_info: exits 0"
assert_contains "$R_OUT" "System Information" "system_info: header present"
assert_contains "$R_OUT" "Done." "system_info: completes"
