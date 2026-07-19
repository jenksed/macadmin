# Testing

macadmin has two test harnesses. The right one to use depends on what you're
testing.

## Zsh runner (`tests/run.zsh`)

The primary harness. Discovers `tests/test_*.zsh`, runs each in a
subprocess, captures exit code and output.

Each test file:

```zsh
#!/usr/bin/env zsh
# shellcheck shell=bash

emulate -L zsh
set -o errexit -o nounset -o pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/assert.zsh"

# Mock system tools by injecting tests/mocks into PATH
export PATH="$SCRIPT_DIR/mocks:$PATH"

pass "boot"

# run_cmd "<prefix>" runs `<prefix> -- <cmd...>` and captures exit + stdout
out=$(run_cmd "system-info" -- zsh "$SCRIPT_DIR/../scripts/system_info.zsh")
assert_exit0 "$?"

# assert_contains <haystack> <needle>
assert_contains "$out" "Darwin"
```

`tests/assert.zsh` provides `pass`, `fail`, `run_cmd`, `assert_exit0`,
`assert_contains`. Extend with new helpers rather than reinventing.

Mocks live in `tests/mocks/`. A mock is a shell script that imitates the
real tool. `make test` does `chmod +x tests/mocks/*` before running, so mocks
can be edited freely.

## Bats library tests (`tests/lib/*.bats`)

Used for library-only tests where shell function assertions are more
ergonomic in bats. Not every library needs bats coverage — duplicate only
when bats is genuinely more comfortable than the zsh runner.

```bash
@test "macadmin_path_cache returns $HOME/Library/Caches" {
  source lib/paths.zsh
  result="$(macadmin_path_cache)"
  [[ "$result" == "$HOME/Library/Caches" ]]
}
```

## Coverage

`make coverage` lists commands and reports which lack tests:

```
Coverage: 7 / 8 commands have tests
Untested: brew-tools
```

Target: 100% command coverage.

## Linting

`make lint` runs shellcheck and shfmt in diff mode. `make format` auto-fixes.

## CI

GitHub Actions runs `make ci` (= lint + test + coverage) on every push and PR.
See `.github/workflows/ci.yml`.