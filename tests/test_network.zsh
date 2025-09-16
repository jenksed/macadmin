#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh services
assert_exit0 $R_STATUS "network: services exits 0"
assert_contains "$R_OUT" "Listing network services" "network: announces listing"
assert_contains "$R_OUT" "Wi-Fi" "network: includes Wi-Fi"

