#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/brew_tools.zsh check
assert_exit0 $R_STATUS "brew_tools: check exits 0"
assert_contains "$R_OUT" "Homebrew found" "brew_tools: detects brew"

PATH="$HERE/mocks:$PATH" run_cmd R2 -- zsh scripts/brew_tools.zsh bundle
assert_exit0 $R2_STATUS "brew_tools: bundle exits 0"
assert_contains "$R2_OUT" "brew bundle (mock)" "brew_tools: bundle uses mock"

