#!/usr/bin/env zsh
# tests/test_disk.zsh — Release 0.5 disk.zsh tests.
# Covers 'largest' (top-N by size) and 'duplicates' (sha256 grouping
# with --delete safety gates).
emulate -L zsh
setopt errexit nounset pipefail

HERE=${0:a:h}
source "$HERE/assert.zsh"

FIX="$HERE/fixtures/disk_test"

# 1. --help exits 0 and lists subcommands
PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/disk.zsh help
assert_exit0 $R_STATUS "disk: help exits 0"
assert_contains "$R_OUT" "largest" "disk: help mentions largest"
assert_contains "$R_OUT" "duplicates" "disk: help mentions duplicates"

# 2. largest: default limit returns 3 fixture dirs in size-desc order
PATH="$HERE/mocks:$PATH" run_cmd R2 -- zsh scripts/disk.zsh largest --path "$FIX"
assert_exit0 $R2_STATUS "disk: largest exits 0"
assert_contains "$R2_OUT" "big" "disk: largest finds big dir"
assert_contains "$R2_OUT" "medium" "disk: largest finds medium dir"
assert_contains "$R2_OUT" "small" "disk: largest finds small dir"
# Order check: big should appear before small in the output.
big_pos=$(print -r -- "$R2_OUT" | grep -n 'big' | head -1 | cut -d: -f1)
small_pos=$(print -r -- "$R2_OUT" | grep -n 'small' | head -1 | cut -d: -f1)
if (( big_pos < small_pos )); then
  pass "disk: largest orders big before small"
else
  print -r -- "big at $big_pos, small at $small_pos"
  fail "disk: largest ordering"
fi

# 3. largest --limit 1 returns only the top entry
PATH="$HERE/mocks:$PATH" run_cmd R3 -- zsh scripts/disk.zsh largest --path "$FIX" --limit 1
assert_exit0 $R3_STATUS "disk: largest --limit exits 0"
n=$(print -r -- "$R3_OUT" | grep -cE '/disk_test/[a-z]+$')
if (( n == 1 )); then
  pass "disk: largest --limit 1 returns 1 dir"
else
  print -r -- "expected 1, got $n"
  fail "disk: largest --limit 1 count"
fi

# 4. largest --json shape
PATH="$HERE/mocks:$PATH" MACADMIN_JSON=1 run_cmd R4 -- zsh scripts/disk.zsh largest --path "$FIX"
assert_exit0 $R4_STATUS "disk: largest --json exits 0"
assert_contains "$R4_OUT" '"path":' "disk: largest --json has path"
assert_contains "$R4_OUT" '"size_bytes":' "disk: largest --json has size_bytes"
assert_contains "$R4_OUT" '"size_kb":' "disk: largest --json has size_kb"

# 5. largest --pretty valid JSON array
PATH="$HERE/mocks:$PATH" run_cmd R5 -- zsh scripts/disk.zsh largest --path "$FIX" --pretty --json
assert_exit0 $R5_STATUS "disk: largest --pretty exits 0"
python3 - "$R5_OUT" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    parsed = json.loads(raw)
    if not isinstance(parsed, list) or len(parsed) != 3:
        print(f'not ok - disk largest pretty: bad shape {type(parsed).__name__}/{len(parsed) if isinstance(parsed, list) else "?"}')
        sys.exit(1)
    print('ok - disk largest pretty json parses as array of 3')
except Exception as e:
    print(f'not ok - disk largest pretty parse failed: {e}')
    sys.exit(1)
PY

# 6. largest missing --path exits EX_NOINPUT (66)
PATH="$HERE/mocks:$PATH" run_cmd R6 -- zsh scripts/disk.zsh largest --path /no/such/path
if (( R6_STATUS == 66 )); then
  pass "disk: largest missing path exits 66"
else
  print -r -- "expected 66, got $R6_STATUS"
  fail "disk: largest missing path exit code"
fi

# 7. duplicates: detects the two 2-byte files as a single group
PATH="$HERE/mocks:$PATH" run_cmd R7 -- zsh scripts/disk.zsh duplicates --path "$FIX"
assert_exit0 $R7_STATUS "disk: duplicates exits 0"
assert_contains "$R7_OUT" "file3.txt" "disk: duplicates finds big/file3.txt"
assert_contains "$R7_OUT" "small/file1.txt" "disk: duplicates finds small/file1.txt"

# 8. duplicates --delete without --yes exits EX_NOPERM (77)
PATH="$HERE/mocks:$PATH" run_cmd R8 -- zsh scripts/disk.zsh duplicates --path "$FIX" --delete
if (( R8_STATUS == 77 )); then
  pass "disk: duplicates --delete without --yes exits 77"
else
  print -r -- "expected 77, got $R8_STATUS"
  fail "disk: duplicates --delete exit code"
fi
assert_contains "$R8_OUT" "--delete requires --yes" "disk: duplicates error message"

# 9. duplicates --delete --protect (even with --yes) is blocked
MACADMIN_PROTECT=1 PATH="$HERE/mocks:$PATH" run_cmd R9 -- zsh scripts/disk.zsh duplicates --path "$FIX" --delete --yes
if (( R9_STATUS == 77 )); then
  pass "disk: duplicates --protect blocks --delete even with --yes"
else
  print -r -- "expected 77, got $R9_STATUS"
  fail "disk: duplicates --protect exit code"
fi
assert_contains "$R9_OUT" "--protect blocks --delete" "disk: duplicates protect message"

# 10. duplicates --delete --yes actually deletes the duplicate (one per group)
# IMPORTANT: use a temp copy of the fixtures so we don't damage the repo's
# committed fixtures.
DUP_TMP=$(mktemp -d -t disktest.XXXXXX)
cp -R "$FIX" "$DUP_TMP/data"
PATH="$HERE/mocks:$PATH" MACADMIN_YES=1 run_cmd R10 -- zsh scripts/disk.zsh duplicates --path "$DUP_TMP/data" --delete
assert_exit0 $R10_STATUS "disk: duplicates --delete --yes exits 0"
# After delete: big/file3.txt kept (first), small/file1.txt deleted.
[[ -f "$DUP_TMP/data/big/file3.txt" ]] && pass "disk: duplicates kept big/file3.txt" \
  || fail "disk: duplicates kept big/file3.txt"
if [[ -f "$DUP_TMP/data/small/file1.txt" ]]; then
  fail "disk: duplicates should have deleted small/file1.txt"
else
  pass "disk: duplicates deleted small/file1.txt"
fi
rm -rf "$DUP_TMP"

# 11. Dispatcher routing: macadmin disk ...
run_cmd R11 -- zsh bin/macadmin disk largest --path "$FIX" --json
assert_exit0 $R11_STATUS "disk: dispatcher route exits 0"
assert_contains "$R11_OUT" '"path":' "disk: dispatcher emits JSON"
