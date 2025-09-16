#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/settings_ui.zsh --apply
assert_exit0 $R_STATUS "settings_ui: apply exits 0"
assert_contains "$R_OUT" "Applying Finder settings" "settings_ui: finder"
assert_contains "$R_OUT" "defaults(mock)" "settings_ui: used defaults mock"

