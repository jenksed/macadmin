#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

# services list
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh services
assert_exit0 $R_STATUS "network: services exits 0"
assert_contains "$R_OUT" "Listing network services" "network: announces listing"
assert_contains "$R_OUT" "Wi-Fi" "network: includes Wi-Fi"

# wifi: dry-run allows without --yes
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh wifi --off --dry-run
assert_exit0 $R_STATUS "network: wifi dry-run exits 0"
assert_contains "$R_OUT" "networksetup -setairportpower" "network: wifi shows planned airportpower command"

# wifi: refuses without --yes when not dry-run
{
  set +e
  PATH="$HERE/mocks:$PATH" zsh scripts/network.zsh wifi --on >"$HERE/.wifi_test.out" 2>&1
  st=$?
}
out=$(cat "$HERE/.wifi_test.out" 2>/dev/null || true)
if (( st == 77 )); then pass "network: wifi requires --yes when not dry-run"; else print -r -- "status=$st"; fail "network: wifi requires --yes when not dry-run"; fi

# dns flush dry-run
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh dns --flush --dry-run
assert_exit0 $R_STATUS "network: dns flush dry-run exits 0"
assert_contains "$R_OUT" "dscacheutil -flushcache" "network: dns flush invokes dscacheutil"
assert_contains "$R_OUT" "killall -HUP mDNSResponder" "network: dns flush signals mDNSResponder"

# diag quick (with mocks to succeed)
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh diag --quick
assert_exit0 $R_STATUS "network: diag quick exits 0"
assert_contains "$R_OUT" "Gateway:" "network: diag quick shows gateway"

# diag quick json
PATH="$HERE/mocks:$PATH" MACADMIN_JSON=1 run_cmd R -- zsh scripts/network.zsh diag --quick
assert_exit0 $R_STATUS "network: diag quick json exits 0"
assert_contains "$R_OUT" '"check":"quick"' "network: diag quick json has check key"
assert_contains "$R_OUT" '"ping_ok":true' "network: diag quick json has ping_ok true"
