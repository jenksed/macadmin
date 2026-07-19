#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
# venv_finder.zsh - find Python virtual environments
#
# Release 0.7 first-class macadmin venv finder. Replaces
# jenksed/mac-scripts/bin/venv-finder (which used GNU find -printf,
# date -d, du -sb and emitted malformed JSON).
#
# Detection: a directory containing pyvenv.cfg (PEP 405) or
# conda-meta/history (conda env).
#
# Usage:
#   macadmin venv-finder [--path <root>] [--json|--pretty]
#                          [--min-size <bytes>] [--ignore <pattern>...]
#                          [--limit N]

emulate -L zsh
# NOTE: errexit intentionally disabled. This script pipelines
# through subshells extensively; we check exit codes at the
# appropriate places rather than relying on errexit propagation.
set +o errexit

SCRIPT_DIR=${0:a:h}
REPO_DIR=${SCRIPT_DIR:h}
LIB_DIR="$REPO_DIR/lib"

source "$LIB_DIR/common.zsh" 2>/dev/null || true
source "$LIB_DIR/argparse.zsh" 2>/dev/null || true
source "$LIB_DIR/exitcodes.zsh" 2>/dev/null || true
source "$LIB_DIR/log.zsh" 2>/dev/null || true

macadmin_parse_globals "$@" 2>/dev/null || true
# Guard against empty array (zsh quirk).
if (( ${#MACADMIN_ARGS[@]} > 0 )); then
  set -- "${MACADMIN_ARGS[@]}"
else
  set --
fi
require_macos || exit 1

usage() {
  cat <<'EOF'
venv_finder.zsh - find Python virtual environments under <path>

Usage:
  venv_finder.zsh [options]

Options:
  --path <root>       Root directory to search (default: current directory
                       or $VENV_FINDER_DEFAULT_PATH from config)
  --min-size <bytes>  Minimum size in bytes (default: 1024)
  --ignore <pattern>  Skip paths matching pattern (can be repeated)
  --limit N           Show at most N results (default: unlimited)
  --json              Emit one JSON object per line (compact)
  --pretty            Emit a single pretty-printed JSON array
  -h, --help          Show this help

Detection: a directory is considered a venv if it contains:
  pyvenv.cfg (PEP 405 standard venv) OR conda-meta/history (conda env)

Output columns (human-readable): size  type  path
Examples:
  venv_finder.zsh --path ~/Projects
  venv_finder.zsh --path . --json | jq -r .path
  venv_finder.zsh --path ~/Projects --pretty --limit 10
EOF
}

# Parse args.
opt_path=""
opt_min_size=1024
typeset -i opt_limit=0
typeset -i opt_json=${MACADMIN_JSON:-0} opt_pretty=0
typeset -a opt_ignore=()

typeset -a _args
_args=("$@")
typeset -i _i=1
typeset -i _expect_value=0
typeset _expect_flag=""
while (( _i <= ${#_args[@]} )); do
  local arg="${_args[_i]}"
  if (( _expect_value )); then
    case "$_expect_flag" in
      --path) opt_path="$arg" ;;
      --min-size) opt_min_size="$arg" ;;
      --limit) opt_limit="$arg" ;;
      --ignore) opt_ignore+=("$arg") ;;
    esac
    _expect_value=0
    _expect_flag=""
    (( _i++ ))
    continue
  fi
  case "$arg" in
    -h|--help) usage; exit ${EX_OK:-0} ;;
    --path)
      _expect_value=1; _expect_flag="--path" ;;
    --path=*) opt_path="${arg#*=}" ;;
    --min-size)
      _expect_value=1; _expect_flag="--min-size" ;;
    --min-size=*) opt_min_size="${arg#*=}" ;;
    --limit)
      _expect_value=1; _expect_flag="--limit" ;;
    --limit=*) opt_limit="${arg#*=}" ;;
    --ignore)
      _expect_value=1; _expect_flag="--ignore" ;;
    --ignore=*) opt_ignore+=("${arg#*=}") ;;
    --json) opt_json=1 ;;
    --pretty) opt_pretty=1 ;;
    --quiet|--verbose|--dry-run|--yes|--protect) : ;;
    *)
      print -r -- "[ERROR] venv_finder: unknown arg: $arg" >&2
      usage >&2
      exit ${EX_USAGE:-64}
      ;;
  esac
  (( _i++ ))
done

# Resolve search root: --path > VENV_FINDER_DEFAULT_PATH > $PWD.
if [[ -z "$opt_path" ]]; then
  opt_path="${VENV_FINDER_DEFAULT_PATH:-.}"
fi
opt_path="${opt_path:A}"

if [[ ! -d "$opt_path" ]]; then
  print -r -- "[ERROR] path not found: $opt_path" >&2
  exit ${EX_NOINPUT:-66}
fi

# ---------------------------------------------------------------------------
# Detection (uses a temp file for output to avoid command-substitution
# pitfalls with errexit-disabled function output capture).
# ---------------------------------------------------------------------------

# Validate that $d/pyvenv.cfg is a real PEP 405 venv marker. The spec
# (§4) requires the file to contain `home = <path>` pointing at the
# Python interpreter the venv was created against. Files lacking that
# key are poisoned fixtures, stale state, or notes masquerading as a
# venv — they must not match. (Regression: tests/fixtures/venvs/random_dir)
_has_pyvenv_home() {
  local cfg="$1/pyvenv.cfg"
  [[ -f "$cfg" ]] || return 1
  grep -Eq '^[[:space:]]*home[[:space:]]*=' "$cfg"
}

_detect_one() {
  local d="$1"
  # pyvenv.cfg (PEP 405) — must validate contents, not just file existence.
  if _has_pyvenv_home "$d"; then print -r -- "venv"; return 0; fi
  # conda env marker.
  [[ -f "$d/conda-meta/history" ]] && print -r -- "conda" && return 0
  # Legacy venv check: bin/python + bin/activate.
  [[ -x "$d/bin/python" ]] && [[ -f "$d/bin/activate" ]] && print -r -- "venv" && return 0
  return 1
}

# Render a byte count as a human-friendly size string (no awk).
_vf_human_size() {
  local vsz=$1
  if (( vsz >= 1073741824 )); then
    print -r -- "$((vsz / 1073741824 )).$(( (vsz % 1073741824) * 10 / 1073741824 ))G"
  elif (( vsz >= 1048576 )); then
    print -r -- "$((vsz / 1048576 )).$(( (vsz % 1048576) * 10 / 1048576 ))M"
  elif (( vsz >= 1024 )); then
    print -r -- "$((vsz / 1024 )).$(( (vsz % 1024) * 10 / 1024 ))K"
  else
    print -r -- "${vsz}B"
  fi
}

# Stream raw find results into a mktemp'd file so pipeline exit
# codes do not lose rows. The trap guarantees cleanup on any exit.
_raw_tmp=$(mktemp -t venv-finder.XXXXXX) || { print -r -- "[ERROR] mktemp failed" >&2; exit 73; }
trap 'rm -f "$_raw_tmp"' EXIT INT TERM

# Walk the tree, skipping junk dirs.
find -E "$opt_path" \
    \( \
      -path '*/.git' -o \
      -path '*/node_modules' -o \
      -path '*/__pycache__' -o \
      -path '*/.tox' -o \
      -path '*/.pytest_cache' -o \
      -path '*/.mypy_cache' -o \
      -path '*/Library/Caches' -o \
      -path '*/Library/Application Support' -o \
      -name '__pycache__' -o \
      -name '.git' -o \
      -name 'node_modules' -o \
      -name '.tox' -o \
      -name 'site-packages' \
    \) -prune -o \
    -type d -print 2>/dev/null \
| while IFS= read -r d; do
    # NOTE: declare-and-assign on one line. zsh echoes `foo=value` to
    # stdout at scope-end whenever `local foo` and `foo=value` are
    # separated across two lines inside a loop body (for, while, until).
    # Combined `local foo="$(...)"` is safe; bare assignments to an
    # already-declared local also leak. Use ${...:-0} to default empty
    # size to 0 without a separate reassignment.
    local vtype="$(_detect_one "$d")"
    [[ -z "$vtype" ]] && continue
    local sz="${$(du -sk "$d" 2>/dev/null | awk '{print $1 * 1024}'):-0}"
    local tab=$'\t'
    print -r -- "${vtype}${tab}${d}${tab}${sz}"
  done > "$_raw_tmp"

# Read the temp file with apply-filters, write to results.
typeset -a results=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Apply --ignore filters.
    skip=0
    for p in "${opt_ignore[@]}"; do
      if [[ "$line" == *"$p"* ]]; then
        skip=1
        break
      fi
    done
    (( skip )) && continue
    # Apply --min-size. Format: type<TAB>path<TAB>size
    local size_part="${line##*$'\t'}"
    if (( opt_min_size > 0 )) && (( size_part < opt_min_size )); then
      continue
    fi
    results+=("$line")
  done < "$_raw_tmp"

# Sort by size desc, then by path. Pipe through `sort` for stability
# across zsh versions (parameter-expansion sort flags vary).
if (( ${#results[@]} > 0 )); then
  local sorted_text
  sorted_text=$(print -r -- "${(F)results}" | sort -t $'\t' -k3 -n -r)
  results=("${(@f)sorted_text}")
fi

# Apply --limit.
if (( opt_limit > 0 )) && (( ${#results[@]} > opt_limit )); then
  results=("${(@)results[1,opt_limit]}")
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if (( opt_pretty )); then
  print -r -- "["
  typeset -i _first=1
  for line in "${results[@]}"; do
    [[ -z "$line" ]] && continue
    if (( _first )); then _first=0; else print -r -- ","; fi
    IFS=$'\t' read -r vtype vpath vsz <<<"$line"
    print -rn -- "  {\"type\":\"${vtype}\",\"path\":\"${vpath}\",\"size\":${vsz}}"
  done
  if (( ${#results[@]} > 0 )); then print -r -- ""; fi
  print -r -- "]"
elif (( opt_json )); then
  for line in "${results[@]}"; do
    [[ -z "$line" ]] && continue
    IFS=$'\t' read -r vtype vpath vsz <<<"$line"
    print -r -- "{\"type\":\"${vtype}\",\"path\":\"${vpath}\",\"size\":${vsz}}"
  done
else
  # Human-readable: column-aligned.
  printf '%-12s %10s  %s\n' SIZE TYPE PATH
  for line in "${results[@]}"; do
    [[ -z "$line" ]] && continue
    IFS=$'\t' read -r vtype vpath vsz <<<"$line"
    local hsize="$(_vf_human_size "$vsz")"
    printf '%-12s %10s  %s\n' "$hsize" "$vtype" "$vpath"
  done
fi

exit ${EX_OK:-0}