#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
# macadmin command template.
#
# Copy this file to scripts/<name>.zsh (or use `make new-command NAME=<name>`)
# and rename the <name>.zsh - <summary> line below. The dispatcher discovers
# your command by filename: scripts/system_info.zsh -> `macadmin system-info`.

emulate -L zsh
set -o errexit -o nounset -o pipefail

# Locate the macadmin repo root regardless of how the script is invoked.
SCRIPT_DIR=${0:a:h}
REPO_DIR=${SCRIPT_DIR:h}
LIB_DIR="$REPO_DIR/lib"

# Source libraries (safe to source multiple times due to internal guards).
source "$LIB_DIR/common.zsh" 2>/dev/null || true
source "$LIB_DIR/argparse.zsh" 2>/dev/null || true
source "$LIB_DIR/exitcodes.zsh" 2>/dev/null || true
source "$LIB_DIR/log.zsh" 2>/dev/null || true

# Parse global flags. After this, "$@" contains only command-specific args.
# Guard against empty array to avoid `set -- ""` (which leaves $1 as empty).
macadmin_parse_globals "$@" 2>/dev/null || true
if ((${#MACADMIN_ARGS[@]} > 0)); then
  set -- "${MACADMIN_ARGS[@]}"
else
  set --
fi

# macOS-only. Mocked uname output containing "Darwin" is accepted for tests.
require_macos || exit ${EX_OSERR:-71}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

usage()
{
  cat <<'EOF'
_template.zsh - replace this summary with a one-line description

Usage:
  _template.zsh [options]

Flags:
  -h, --help   Show this help

Options:
  --name <str>   Example option: a name to echo back (default: world)

Examples:
  _template.zsh --name alice
  _template.zsh --json

Notes:
  - Honors global env toggles set by dispatcher:
      MACADMIN_DRY_RUN, MACADMIN_YES, MACADMIN_VERBOSE, MACADMIN_JSON,
      MACADMIN_QUIET, MACADMIN_PROTECT, MACADMIN_CONFIG
  - Mutating actions must check MACADMIN_PROTECT and require --yes.
  - Output JSON via macadmin_json_obj / macadmin_json_pretty_obj.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing (per-command)
# ---------------------------------------------------------------------------

opt_name="world"

# Two-pass parse: first pass collects positional args, second pass extracts
# values for flags that need a value (e.g., --name). The two-pass approach
# keeps the template simple while supporting "--flag value" and "--flag=value".

typeset -a _pass1
_pass1=()
typeset -i _expect_value=0
for arg in "$@"; do
  if ((_expect_value)); then
    _pass1+=("$arg")
    _expect_value=0
    continue
  fi
  case "$arg" in
    -h | --help)
      usage
      exit ${EX_OK:-0}
      ;;
    --name)
      _pass1+=("$arg")
      _expect_value=1
      ;;
    --dry-run | --yes | --json | --pretty | --quiet | --protect | --verbose) _pass1+=("$arg") ;;
    --)
      shift
      _pass1+=("$@")
      break
      ;;
    *)
      log_error "unknown arg: $arg" 2>/dev/null || print -r -- "[ERROR] unknown arg: $arg" >&2
      usage >&2
      exit ${EX_USAGE:-64}
      ;;
  esac
done

typeset -i _i=1
while ((_i <= ${#_pass1[@]})); do
  case "${_pass1[_i]}" in
    --name)
      ((_i + 1 <= ${#_pass1[@]})) || {
        print -r -- "[ERROR] --name requires a value" >&2
        exit ${EX_USAGE:-64}
      }
      opt_name="${_pass1[_i + 1]}"
      ((_i += 2))
      ;;
    *) ((_i++)) ;;
  esac
done

# ---------------------------------------------------------------------------
# Action
# ---------------------------------------------------------------------------

if ((MACADMIN_JSON)); then
  macadmin_json_obj greeting="hello" name="$opt_name"
  printf '\n'
else
  print -r -- "hello, $opt_name"
fi

exit ${EX_OK:-0}
