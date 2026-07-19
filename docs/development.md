# Adding a command

```bash
make new-command NAME=disk-largest
```

This creates `scripts/disk_largest.zsh` from `_template.zsh`, replacing
the name placeholders. Then edit it.

## File layout for a new command

```zsh
#!/usr/bin/env zsh
# shellcheck shell=bash
# disk_largest.zsh - one-line description of what this does
#
# Detailed description (optional).

emulate -L zsh
set -o errexit -o nounset -o pipefail

SCRIPT_DIR=${0:a:h}
REPO_DIR=${SCRIPT_DIR:h}
LIB_DIR="$REPO_DIR/lib"

source "$LIB_DIR/common.zsh" 2>/dev/null || true
source "$LIB_DIR/argparse.zsh" 2>/dev/null || true
source "$LIB_DIR/exitcodes.zsh" 2>/dev/null || true
source "$LIB_DIR/log.zsh" 2>/dev/null || true

macadmin_parse_globals "$@"
if (( ${#MACADMIN_ARGS[@]} > 0 )); then
  set -- "${MACADMIN_ARGS[@]}"
else
  set --
fi
require_macos || exit ${EX_OSERR:-71}

usage() {
  cat <<'EOF'
disk_largest.zsh - show the N largest directories under <path>

Usage:
  disk_largest.zsh [--path <dir>] [--limit N] [--json]

Flags:
  --path <dir>   Root directory (default: $HOME)
  --limit N      Number of entries to show (default: 10)
  --json         Emit JSON
  -h, --help     Show this help

Examples:
  disk_largest.zsh --path $HOME --limit 20
  disk_largest.zsh --json
EOF
}

typeset -i opt_limit=10
opt_path="${HOME}"

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit ${EX_OK:-0} ;;
    --path)    # handle value in second pass or inline below
               ;;
    --limit)
      (( $# >= 2 )) || { log_error "--limit requires a value"; exit ${EX_USAGE:-64}; }
      shift; opt_limit="$1"
      ;;
    --json|--dry-run|--yes|--quiet|--verbose|--protect|--pretty) : ;;
    *)
      log_error "unknown arg: $arg"
      usage >&2
      exit ${EX_USAGE:-64}
      ;;
  esac
done
```

## What the dispatcher needs

- File under `scripts/`, extension `.zsh`.
- Filename starts with a letter; not `_*.zsh` (those are excluded from discovery).
- First line of `usage()` heredoc: `<filename without .zsh> - <summary>`.
  The dispatcher extracts this for `macadmin help`.

## What every command must do

1. Honor global env toggles (`MACADMIN_JSON`, `MACADMIN_DRY_RUN`,
   `MACADMIN_YES`, `MACADMIN_PROTECT`, `MACADMIN_VERBOSE`, `MACADMIN_QUIET`).
2. Use shared JSON emitters (`macadmin_json_obj`,
   `macadmin_json_pretty_obj`, etc.) — do not hand-roll JSON.
3. Exit with sysexits codes, not `exit 1`.
4. Provide `--help` and a real `usage()` heredoc.
5. If mutating, gate on `MACADMIN_PROTECT` + require `MACADMIN_YES`.

## What every command must NOT do

1. `rm -rf` over broad paths or paths outside an allowlist.
2. Use `kill` with unquoted user input.
3. Write to `~/Desktop` automatically.
4. Print secrets or hardcoded credentials.
5. Use `sudo` without explicit `require_sudo`.
6. `set -e` and silently continue after a failed command.

## Test pattern

Create `tests/test_disk_largest.zsh`:

```zsh
#!/usr/bin/env zsh
emulate -L zsh
set -o errexit -o nounset -o pipefail
SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/assert.zsh"

pass "disk-largest-helps"
out=$(zsh "$SCRIPT_DIR/../scripts/disk_largest.zsh" --help 2>&1)
assert_exit0 $?
assert_contains "$out" "disk_largest.zsh"

pass "disk-largest-json"
out=$(zsh "$SCRIPT_DIR/../scripts/disk_largest.zsh" --path /tmp --limit 3 --json 2>&1)
assert_exit0 $?
# Validate JSON shape with jq if available, else just check for braces.
[[ "$out" == \{* ]]
```

Run: `make test`. Coverage: `make coverage`.

## Naming

- Filename: `scripts/<name_with_underscores>.zsh`
- Command name: `macadmin <name-with-dashes>`
- Dispatcher maps via simple `_/-` substitution; names match 1:1.
- Use lowercase, hyphenated command names; underscore filenames.
- Verbs in command names (`disk largest`, `files rename`) are namespaces —
  see how `network.zsh` handles `wifi`, `dns`, `services`, `diag`.