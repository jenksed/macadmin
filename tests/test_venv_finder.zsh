#!/usr/bin/env zsh
# tests/test_venv_finder.zsh — tests for scripts/venv_finder.zsh
# Release 0.7. Exercises the PEP 405 pyvenv.cfg content-validation
# regression (tests/fixtures/venvs/random_dir) plus JSON/pretty output,
# filtering, error paths, and dispatcher wiring.
emulate -L zsh
setopt errexit nounset pipefail

HERE=${0:a:h}
source "$HERE/assert.zsh"

FIX="$HERE/fixtures/venvs"

# 1. Dispatcher auto-discovers scripts/venv_finder.zsh as `venv-finder`
run_cmd R -- zsh bin/macadmin venv-finder --help
assert_exit0 $R_STATUS "venv-finder: dispatcher routes to --help"
assert_contains "$R_OUT" "venv_finder.zsh" "venv-finder: help shows usage"

# 2. Happy path: detects the two real venvs in human-readable mode
run_cmd R -- zsh scripts/venv_finder.zsh --path "$FIX"
assert_exit0 $R_STATUS "venv-finder: scan exits 0"
assert_contains "$R_OUT" "proj1/venv" "venv-finder: detects proj1/venv"
assert_contains "$R_OUT" "proj2/.venv" "venv-finder: detects proj2/.venv"

# 3. REGRESSION: random_dir has a pyvenv.cfg but NO 'home =' directive
# (PEP 405 §4 requires it). Must NOT be reported as a venv.
if print -r -- "$R_OUT" | grep -Fq "random_dir"; then
  fail "venv-finder: REGRESSION random_dir (poisoned pyvenv.cfg) was reported"
else
  pass "venv-finder: rejects random_dir (poisoned pyvenv.cfg)"
fi

# 4. --json: one JSON object per line, exactly 2 venvs
run_cmd R -- zsh scripts/venv_finder.zsh --path "$FIX" --json
assert_exit0 $R_STATUS "venv-finder: --json exits 0"
n=$(print -r -- "$R_OUT" | grep -c '^{')
if (( n == 2 )); then
  pass "venv-finder: --json emits 2 lines"
else
  print -r -- "expected 2 lines, got $n"
  fail "venv-finder: --json line count"
fi
assert_contains "$R_OUT" '"type":"venv"' "venv-finder: --json has type field"
assert_contains "$R_OUT" '"path"' "venv-finder: --json has path field"
assert_contains "$R_OUT" '"size"' "venv-finder: --json has size field"

# 5. --pretty: emits a single JSON array
run_cmd R -- zsh scripts/venv_finder.zsh --path "$FIX" --pretty
assert_exit0 $R_STATUS "venv-finder: --pretty exits 0"
# Pretty output starts with "[" (possibly followed by whitespace/newline)
first=$(print -r -- "$R_OUT" | head -n1)
if [[ "$first" == "[" ]]; then
  pass "venv-finder: --pretty starts with ["
else
  print -r -- "expected first line '[', got: $first"
  fail "venv-finder: --pretty first line"
fi
# Pretty output should have exactly 2 comma-separated objects
n=$(print -r -- "$R_OUT" | grep -c '"type":"venv"')
if (( n == 2 )); then
  pass "venv-finder: --pretty has 2 objects"
else
  print -r -- "expected 2 objects, got $n"
  fail "venv-finder: --pretty object count"
fi
# Pretty output ends with "]"
last=$(print -r -- "$R_OUT" | grep -v '^$' | tail -n1)
if [[ "$last" == "]" ]]; then
  pass "venv-finder: --pretty ends with ]"
else
  print -r -- "expected last line ']', got: $last"
  fail "venv-finder: --pretty last line"
fi

# 6. --limit N truncates results
run_cmd R -- zsh scripts/venv_finder.zsh --path "$FIX" --limit 1 --json
assert_exit0 $R_STATUS "venv-finder: --limit exits 0"
n=$(print -r -- "$R_OUT" | grep -c '^{')
if (( n == 1 )); then
  pass "venv-finder: --limit 1 returns 1 line"
else
  print -r -- "expected 1 line, got $n"
  fail "venv-finder: --limit 1 line count"
fi

# 7. --ignore <pattern> skips matching paths
run_cmd R -- zsh scripts/venv_finder.zsh --path "$FIX" --ignore proj1 --json
assert_exit0 $R_STATUS "venv-finder: --ignore exits 0"
if print -r -- "$R_OUT" | grep -Fq "proj1"; then
  fail "venv-finder: --ignore proj1 should skip proj1"
else
  pass "venv-finder: --ignore proj1 skips proj1"
fi
assert_contains "$R_OUT" "proj2" "venv-finder: --ignore proj1 keeps proj2"

# 8. --min-size excludes smaller entries. Fixtures are 4KB each;
# 99999 must yield zero results.
run_cmd R -- zsh scripts/venv_finder.zsh --path "$FIX" --min-size 99999 --json
assert_exit0 $R_STATUS "venv-finder: --min-size exits 0"
if [[ -z "$R_OUT" ]]; then
  pass "venv-finder: --min-size 99999 excludes 4KB fixtures"
else
  print -r -- "expected empty, got: $R_OUT"
  fail "venv-finder: --min-size 99999 should exclude 4KB fixtures"
fi

# 9. --path <missing> exits EX_NOINPUT (66).
run_cmd R -- zsh scripts/venv_finder.zsh --path /no/such/path
if (( R_STATUS == 66 )); then
  pass "venv-finder: missing --path exits 66 (EX_NOINPUT)"
else
  print -r -- "expected exit 66, got $R_STATUS"
  fail "venv-finder: missing --path exit code"
fi

# 10. Unknown arg exits EX_USAGE (64).
run_cmd R -- zsh scripts/venv_finder.zsh --bogus
if (( R_STATUS == 64 )); then
  pass "venv-finder: unknown arg exits 64 (EX_USAGE)"
else
  print -r -- "expected exit 64, got $R_STATUS"
  fail "venv-finder: unknown arg exit code"
fi
assert_contains "$R_OUT" "unknown arg: --bogus" "venv-finder: unknown arg error message"

# 11. Dispatcher-level invocation also works (full routing path)
run_cmd R -- zsh bin/macadmin venv-finder --path "$FIX" --json
assert_exit0 $R_STATUS "venv-finder: dispatcher exit 0"
assert_contains "$R_OUT" "proj1/venv" "venv-finder: dispatcher detects proj1"
assert_contains "$R_OUT" "proj2/.venv" "venv-finder: dispatcher detects proj2"
