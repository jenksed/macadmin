#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

DRY_RUN=1 run_cmd R -- zsh scripts/cleanup.zsh --user --dry-run
assert_exit0 $R_STATUS "cleanup: user dry-run exits 0"
assert_contains "$R_OUT" "Cleaning user caches" "cleanup: announces user caches"
assert_contains "$R_OUT" "Cleanup complete" "cleanup: completes"

