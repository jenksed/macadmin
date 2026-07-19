#!/usr/bin/env zsh
# tests/test_network_ping.zsh — Release 0.7 ping subcommand tests.
# Covers single host, multi-host, --count, --timeout, --json output,
# --pretty output, and error paths.
emulate -L zsh
setopt errexit nounset pipefail

HERE=${0:a:h}
source "$HERE/assert.zsh"

# 1. --help exits 0 and shows usage
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh ping --help
assert_exit0 $R_STATUS "network ping: --help exits 0"
assert_contains "$R_OUT" "ping" "network ping: help mentions ping"

# 2. Single host, human-readable, mock returns success
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh ping 127.0.0.1
assert_exit0 $R_STATUS "network ping: single host exits 0"
assert_contains "$R_OUT" "127.0.0.1: 1/1 received" "network ping: shows 1/1 received"
assert_contains "$R_OUT" "min/avg/max" "network ping: shows min/avg/max"

# 3. --count N passes -c N to ping (verified by mock output count)
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh ping --count 4 127.0.0.1
assert_exit0 $R_STATUS "network ping: --count exits 0"
assert_contains "$R_OUT" "4 packets transmitted" "network ping: --count 4 sent 4 packets"

# 4. --timeout SEC translates to -W (SEC*1000) ms (mock ignores -W but
#    the call should not fail)
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh ping --timeout 2 127.0.0.1
assert_exit0 $R_STATUS "network ping: --timeout exits 0"

# 5. Multi-host: 2 hosts -> 2 JSON objects, exit 0 (mock succeeds for both)
PATH="$HERE/mocks:$PATH" MACADMIN_JSON=1 run_cmd R -- zsh scripts/network.zsh ping 127.0.0.1 10.0.0.1
assert_exit0 $R_STATUS "network ping: multi-host exits 0"
n=$(print -r -- "$R_OUT" | grep -c '^{')
if (( n == 2 )); then
  pass "network ping: multi-host emits 2 JSON objects"
else
  print -r -- "expected 2 JSON objects, got $n"
  fail "network ping: multi-host emits 2 JSON objects"
fi
assert_contains "$R_OUT" '"host":"127.0.0.1"' "network ping: JSON has 127.0.0.1"
assert_contains "$R_OUT" '"host":"10.0.0.1"' "network ping: JSON has 10.0.0.1"

# 6. JSON shape: every required field present
PATH="$HERE/mocks:$PATH" MACADMIN_JSON=1 run_cmd R -- zsh scripts/network.zsh ping 127.0.0.1
assert_exit0 $R_STATUS "network ping: --json exits 0"
assert_contains "$R_OUT" '"host":' "network ping: --json has host"
assert_contains "$R_OUT" '"transmitted":' "network ping: --json has transmitted"
assert_contains "$R_OUT" '"received":' "network ping: --json has received"
assert_contains "$R_OUT" '"packet_loss":' "network ping: --json has packet_loss"
assert_contains "$R_OUT" '"min_ms":' "network ping: --json has min_ms"
assert_contains "$R_OUT" '"avg_ms":' "network ping: --json has avg_ms"
assert_contains "$R_OUT" '"max_ms":' "network ping: --json has max_ms"
assert_contains "$R_OUT" '"ok":true' "network ping: --json has ok=true"

# 7. --pretty output is valid JSON (one pretty object per host, since
#    ping results are line-delimited across hosts in both modes).
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh ping 127.0.0.1 --pretty --json
assert_exit0 $R_STATUS "network ping: --pretty exits 0"
python3 - "$R_OUT" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    parsed = json.loads(raw)
    if not isinstance(parsed, dict) or 'host' not in parsed:
        print(f'not ok - network ping pretty: bad shape {parsed!r}')
        sys.exit(1)
    if parsed['host'] != '127.0.0.1':
        print(f'not ok - network ping pretty: wrong host {parsed["host"]!r}')
        sys.exit(1)
    print('ok - network ping pretty json parses as object')
except Exception as e:
    print(f'not ok - network ping pretty json parse failed: {e}')
    sys.exit(1)
PY

# 8. Missing host exits EX_USAGE (64)
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh ping
if (( R_STATUS == 64 )); then
  pass "network ping: no host exits 64 (EX_USAGE)"
else
  print -r -- "expected exit 64, got $R_STATUS"
  fail "network ping: no host exit code"
fi
assert_contains "$R_OUT" "at least one host required" "network ping: no host error message"

# 9. Unknown flag exits EX_USAGE
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/network.zsh ping --bogus 127.0.0.1
if (( R_STATUS == 64 )); then
  pass "network ping: unknown flag exits 64 (EX_USAGE)"
else
  print -r -- "expected exit 64, got $R_STATUS"
  fail "network ping: unknown flag exit code"
fi

# 10. Dispatcher routes to network ping
run_cmd R -- zsh bin/macadmin network ping 127.0.0.1 --json
assert_exit0 $R_STATUS "network ping: dispatcher route exits 0"
assert_contains "$R_OUT" '"host":"127.0.0.1"' "network ping: dispatcher emits JSON"
