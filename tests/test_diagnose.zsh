#!/usr/bin/env zsh
# tests/test_diagnose.zsh — Release 0.4 diagnose subcommand tests.
# Covers 'summary', 'cleanup' (filter combinations), 'freeze --dry-run',
# error paths, and dispatcher routing.
emulate -L zsh
setopt errexit nounset pipefail

HERE=${0:a:h}
source "$HERE/assert.zsh"

FIX="$HERE/fixtures/cleanup_test"

# 1. --help exits 0 and lists subcommands
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/diagnose.zsh help
assert_exit0 $R_STATUS "diagnose: help exits 0"
assert_contains "$R_OUT" "summary" "diagnose: help mentions summary"
assert_contains "$R_OUT" "cleanup" "diagnose: help mentions cleanup"
assert_contains "$R_OUT" "freeze" "diagnose: help mentions freeze"

# 2. summary: human-readable, all expected keys present
PATH="$HERE/mocks:$PATH" run_cmd R2 -- zsh scripts/diagnose.zsh summary
assert_exit0 $R2_STATUS "diagnose: summary exits 0"
assert_contains "$R2_OUT" "product_version: 15.6.1" "diagnose: summary product_version"
assert_contains "$R2_OUT" "build: 24G90" "diagnose: summary build"
assert_contains "$R2_OUT" "model_id: Mac14,2" "diagnose: summary model_id"
assert_contains "$R2_OUT" "memory_gb: 8.0" "diagnose: summary memory_gb"
assert_contains "$R2_OUT" "disk_total_gb: 100.0" "diagnose: summary disk_total_gb"
assert_contains "$R2_OUT" "uptime_seconds:" "diagnose: summary uptime_seconds"

# 3. summary --json: every required key present, JSON parseable
PATH="$HERE/mocks:$PATH" MACADMIN_JSON=1 run_cmd R3 -- zsh scripts/diagnose.zsh summary
assert_exit0 $R3_STATUS "diagnose: summary --json exits 0"
assert_contains "$R3_OUT" '"product_version":"15.6.1"' "diagnose: summary --json product_version"
assert_contains "$R3_OUT" '"build":"24G90"' "diagnose: summary --json build"
assert_contains "$R3_OUT" '"model_id":"Mac14,2"' "diagnose: summary --json model_id"
assert_contains "$R3_OUT" '"chip":"Apple M2"' "diagnose: summary --json chip"
assert_contains "$R3_OUT" '"memory_gb":8.0' "diagnose: summary --json memory_gb"
assert_contains "$R3_OUT" '"interfaces":{' "diagnose: summary --json interfaces as nested object"
assert_contains "$R3_OUT" '"en0"' "diagnose: summary --json en0 in interfaces"
assert_contains "$R3_OUT" '"uptime_seconds":' "diagnose: summary --json uptime"
assert_contains "$R3_OUT" '"ts":"' "diagnose: summary --json ts"

# 4. summary --pretty is valid JSON (single object with all fields)
PATH="$HERE/mocks:$PATH" run_cmd R4 -- zsh scripts/diagnose.zsh summary --pretty --json
assert_exit0 $R4_STATUS "diagnose: summary --pretty exits 0"
python3 - "$R4_OUT" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        print('not ok - summary pretty: not an object')
        sys.exit(1)
    for k in ("product_version", "build", "model_id", "chip", "memory_gb",
              "primary_volume", "disk_total_gb", "disk_free_gb", "interfaces",
              "uptime_seconds", "ts"):
        if k not in parsed:
            print(f'not ok - summary pretty: missing {k}')
            sys.exit(1)
    if not isinstance(parsed['interfaces'], dict):
        print('not ok - summary pretty: interfaces is not an object')
        sys.exit(1)
    print('ok - summary pretty json parses; all fields present')
except Exception as e:
    print(f'not ok - summary pretty json parse failed: {e}')
    sys.exit(1)
PY

# 5. cleanup: no filters returns all 4 fixture files
PATH="$HERE/mocks:$PATH" run_cmd R5 -- zsh scripts/diagnose.zsh cleanup --path "$FIX"
assert_exit0 $R5_STATUS "diagnose: cleanup no filters exits 0"
n=$(print -r -- "$R5_OUT" | grep -c '^/')
if (( n == 4 )); then
  pass "diagnose: cleanup no filters returns 4 files"
else
  print -r -- "expected 4 files, got $n"
  fail "diagnose: cleanup no filters returns 4 files"
fi

# 6. cleanup --older-than 7: only old_small.txt (backdated 2025-06-01)
PATH="$HERE/mocks:$PATH" run_cmd R6 -- zsh scripts/diagnose.zsh cleanup --path "$FIX" --older-than 7
assert_exit0 $R6_STATUS "diagnose: cleanup --older-than 7 exits 0"
assert_contains "$R6_OUT" "old_small.txt" "diagnose: cleanup --older-than 7 finds old_small.txt"
if print -r -- "$R6_OUT" | grep -v '^PATH' | grep -v '^/' | grep -q '^.*Scanning'; then :; fi
# Verify NO recent files appear.
if print -r -- "$R6_OUT" | grep -Fq "large.bin"; then
  fail "diagnose: cleanup --older-than 7 should not match recent large.bin"
else
  pass "diagnose: cleanup --older-than 7 excludes recent large.bin"
fi

# 7. cleanup --larger-than 1M: only large.bin (2 MB)
PATH="$HERE/mocks:$PATH" run_cmd R7 -- zsh scripts/diagnose.zsh cleanup --path "$FIX" --larger-than 1M
assert_exit0 $R7_STATUS "diagnose: cleanup --larger-than 1M exits 0"
assert_contains "$R7_OUT" "large.bin | 2M" "diagnose: cleanup --larger-than 1M finds large.bin"
if print -r -- "$R7_OUT" | grep -Fq "medium.bin"; then
  fail "diagnose: cleanup --larger-than 1M should not match 512K medium.bin"
else
  pass "diagnose: cleanup --larger-than 1M excludes 512K medium.bin"
fi

# 8. cleanup --older-than 7 --larger-than 1M: zero matches (no file is both old AND large)
PATH="$HERE/mocks:$PATH" run_cmd R8 -- zsh scripts/diagnose.zsh cleanup --path "$FIX" --older-than 7 --larger-than 1M
assert_exit0 $R8_STATUS "diagnose: cleanup combined filters exits 0"
assert_contains "$R8_OUT" "No files found." "diagnose: combined filters find nothing"

# 9. cleanup --json: one object per matching file with all fields
PATH="$HERE/mocks:$PATH" MACADMIN_JSON=1 run_cmd R9 -- zsh scripts/diagnose.zsh cleanup --path "$FIX" --larger-than 1M
assert_exit0 $R9_STATUS "diagnose: cleanup --json exits 0"
n=$(print -r -- "$R9_OUT" | grep -c '^{')
if (( n == 1 )); then
  pass "diagnose: cleanup --json emits 1 object for --larger-than 1M"
else
  print -r -- "expected 1, got $n"
  fail "diagnose: cleanup --json emits 1 object for --larger-than 1M"
fi
assert_contains "$R9_OUT" '"path":' "diagnose: cleanup --json has path"
assert_contains "$R9_OUT" '"size_bytes":' "diagnose: cleanup --json has size_bytes"
assert_contains "$R9_OUT" '"atime_iso":' "diagnose: cleanup --json has atime_iso"

# 10. cleanup --pretty: valid JSON array
PATH="$HERE/mocks:$PATH" run_cmd R10 -- zsh scripts/diagnose.zsh cleanup --path "$FIX" --larger-than 1M --pretty --json
assert_exit0 $R10_STATUS "diagnose: cleanup --pretty exits 0"
python3 - "$R10_OUT" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    parsed = json.loads(raw)
    if not isinstance(parsed, list):
        print('not ok - cleanup pretty: not an array')
        sys.exit(1)
    if len(parsed) != 1:
        print(f'not ok - cleanup pretty: expected 1 item, got {len(parsed)}')
        sys.exit(1)
    for k in ("path", "size_bytes", "atime_iso"):
        if k not in parsed[0]:
            print(f'not ok - cleanup pretty: missing {k}')
            sys.exit(1)
    print('ok - cleanup pretty json parses as array of 1 object')
except Exception as e:
    print(f'not ok - cleanup pretty json parse failed: {e}')
    sys.exit(1)
PY

# 11. cleanup --path <missing> exits EX_NOINPUT (66)
PATH="$HERE/mocks:$PATH" run_cmd R11 -- zsh scripts/diagnose.zsh cleanup --path /no/such/path
if (( R11_STATUS == 66 )); then
  pass "diagnose: cleanup missing --path exits 66 (EX_NOINPUT)"
else
  print -r -- "expected exit 66, got $R11_STATUS"
  fail "diagnose: cleanup missing --path exit code"
fi
assert_contains "$R11_OUT" "path not found" "diagnose: cleanup missing --path error message"

# 12. cleanup --larger-than with invalid value exits EX_USAGE (64)
PATH="$HERE/mocks:$PATH" run_cmd R12 -- zsh scripts/diagnose.zsh cleanup --path "$FIX" --larger-than 99XB
if (( R12_STATUS == 64 )); then
  pass "diagnose: cleanup invalid --larger-than exits 64"
else
  print -r -- "expected exit 64, got $R12_STATUS"
  fail "diagnose: cleanup invalid --larger-than exit code"
fi

# 13. freeze --dry-run: prints all planned actions, never executes
PATH="$HERE/mocks:$PATH" run_cmd R13 -- zsh scripts/diagnose.zsh freeze --dry-run
assert_exit0 $R13_STATUS "diagnose: freeze --dry-run exits 0"
assert_contains "$R13_OUT" "Planned output directory:" "diagnose: freeze --dry-run announces output dir"
assert_contains "$R13_OUT" "system_profiler SPHardwareDataType" "diagnose: freeze --dry-run lists system_profiler"
assert_contains "$R13_OUT" "sudo spindump" "diagnose: freeze --dry-run lists spindump (sudo)"
assert_contains "$R13_OUT" "log show --last 15m" "diagnose: freeze --dry-run lists log show"
assert_contains "$R13_OUT" "NOT yet implemented" "diagnose: freeze notes deferred implementation"

# 14. Unknown subcommand exits EX_USAGE
PATH="$HERE/mocks:$PATH" run_cmd R14 -- zsh scripts/diagnose.zsh bogus
if (( R14_STATUS == 64 )); then
  pass "diagnose: unknown subcommand exits 64 (EX_USAGE)"
else
  print -r -- "expected exit 64, got $R14_STATUS"
  fail "diagnose: unknown subcommand exit code"
fi

# 15. Dispatcher routing: macadmin diagnose <subcommand>
run_cmd R15 -- zsh bin/macadmin diagnose summary --json
assert_exit0 $R15_STATUS "diagnose: dispatcher route exits 0"
assert_contains "$R15_OUT" '"product_version"' "diagnose: dispatcher emits product_version"
