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


# services: JSON output
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh services --json
assert_exit0 $R_STATUS "network: services json exits 0"
assert_contains "$R_OUT" '"service":"Wi-Fi"' "network: services json contains Wi-Fi"
assert_contains "$R_OUT" '"enabled":true' "network: services json marks enabled"

# dns: JSON output (dry-run)
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh dns --flush --dry-run --json
assert_exit0 $R_STATUS "network: dns flush json exits 0"
assert_contains "$R_OUT" '"action":"dns_flush"' "network: dns flush json has action"
assert_contains "$R_OUT" '"ok":true' "network: dns flush json ok true"

# wifi: honors config override for custom service name
tmp="$HERE/tmp_net_ovr.$$"; rm -rf "$tmp"; mkdir -p "$tmp/home" "$tmp/bin"
cat > "$tmp/home/.macadminrc" <<EOF
[network]
wifi_default_service = "Corp Wi-Fi"
EOF
cat > "$tmp/bin/networksetup" <<'EOF'
#!/usr/bin/env zsh
emulate -L zsh
case "$1" in
  -listallnetworkservices)
    cat <<LS
An asterisk (*) denotes that a network service is disabled.
Corp Wi-Fi
Ethernet
Thunderbolt Bridge
LS
    ;;
  -listnetworkserviceorder)
    cat <<ORD
(1) Corp Wi-Fi
      Hardware Port: Wi-Fi, Device: en0
(2) Ethernet
      Hardware Port: Ethernet, Device: en1
ORD
    ;;
  -listallhardwareports)
    cat <<HP
Hardware Port: Wi-Fi
Device: en0
HP
    ;;
  -setairportpower)
    print -r -- "setairportpower(mock-ovr): $*" ;;
  *) print -r -- "networksetup(mock-ovr): $*" ;;

esac
exit 0
EOF
chmod +x "$tmp/bin/networksetup"
HOME="$tmp/home" PATH="$tmp/bin:$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh wifi --off --dry-run
assert_exit0 $R_STATUS "network: wifi override dry-run exits 0"
assert_contains "$R_OUT" "networksetup -setairportpower en0 off" "network: wifi override uses en0 and off"
