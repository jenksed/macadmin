#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/os_update.zsh --list
assert_exit0 $R_STATUS "os_update: --list exits 0"
assert_contains "$R_OUT" "Listing available updates" "os_update: shows listing header"
assert_contains "$R_OUT" "Mock Update" "os_update: uses mock softwareupdate"

