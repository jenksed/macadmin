#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

run_cmd R -- zsh bin/macadmin help
assert_exit0 $R_STATUS "dispatcher: help exits 0"
assert_contains "$R_OUT" "macOS admin utilities dispatcher" "dispatcher: help text"

