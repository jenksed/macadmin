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

# doctor: human-readable output exits 0 (mock returns clean)
PATH="$HERE/mocks:$PATH" run_cmd R3 -- zsh scripts/brew_tools.zsh doctor
assert_exit0 $R3_STATUS "brew_tools: doctor exits 0"
assert_contains "$R3_OUT" "system is ready to brew" "brew_tools: doctor prints mock output"

# doctor --json emits the structured event with exit_code + output
PATH="$HERE/mocks:$PATH" MACADMIN_JSON=1 run_cmd R4 -- zsh scripts/brew_tools.zsh doctor
assert_exit0 $R4_STATUS "brew_tools: doctor --json exits 0"
assert_contains "$R4_OUT" '"event":"brew_doctor"' "brew_tools: doctor --json has event"
assert_contains "$R4_OUT" '"ok":true' "brew_tools: doctor --json has ok=true"
assert_contains "$R4_OUT" '"exit_code":"0"' "brew_tools: doctor --json has exit_code"
assert_contains "$R4_OUT" '"output":' "brew_tools: doctor --json has output field"

# list: human-readable output is the raw `brew list` rows
PATH="$HERE/mocks:$PATH" run_cmd R5 -- zsh scripts/brew_tools.zsh list
assert_exit0 $R5_STATUS "brew_tools: list exits 0"
assert_contains "$R5_OUT" "git 2.43.0" "brew_tools: list shows git 2.43.0"
assert_contains "$R5_OUT" "jq 1.7.1" "brew_tools: list shows jq 1.7.1"

# list --json emits one JSON object per formula
PATH="$HERE/mocks:$PATH" MACADMIN_JSON=1 run_cmd R6 -- zsh scripts/brew_tools.zsh list
assert_exit0 $R6_STATUS "brew_tools: list --json exits 0"
n=$(print -r -- "$R6_OUT" | grep -c '^{')
if (( n == 4 )); then
  pass "brew_tools: list --json emits 4 formulae"
else
  print -r -- "expected 4 formulae, got $n"
  fail "brew_tools: list --json emits 4 formulae"
fi
assert_contains "$R6_OUT" '"formula":"git"' "brew_tools: list --json has git"
assert_contains "$R6_OUT" '"version":"2.43.0"' "brew_tools: list --json has git version"
assert_contains "$R6_OUT" '"formula":"jq"' "brew_tools: list --json has jq"

# list --json --pretty emits a single JSON array of objects
PATH="$HERE/mocks:$PATH" run_cmd R7 -- zsh scripts/brew_tools.zsh list --pretty --json
assert_exit0 $R7_STATUS "brew_tools: list --pretty exits 0"
python3 - "$R7_OUT" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    parsed = json.loads(raw)
    if not isinstance(parsed, list):
        print('not ok - brew_tools list pretty: not a JSON array')
        sys.exit(1)
    if len(parsed) != 4 or 'formula' not in parsed[0] or 'version' not in parsed[0]:
        print(f'not ok - brew_tools list pretty: bad shape {parsed}')
        sys.exit(1)
    print('ok - brew_tools list pretty json parses as array of 4 objects')
except Exception as e:
    print(f'not ok - brew_tools list pretty json parse failed: {e}')
    sys.exit(1)
PY

