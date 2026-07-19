#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
# disk.zsh - disk usage helpers
#
# Release 0.5. Two subcommands:
#   disk largest [--path <root>] [--limit N] [--json|--pretty]
#   disk duplicates [--path <root>] [--delete] [--yes] [--protect] [--json|--pretty]

emulate -L zsh
set -o errexit -o nounset -o pipefail

SCRIPT_DIR=${0:a:h}
REPO_DIR=${SCRIPT_DIR:h}
LIB_DIR="$REPO_DIR/lib"

source "$LIB_DIR/common.zsh"
source "$LIB_DIR/argparse.zsh"
source "$LIB_DIR/exitcodes.zsh"
source "$LIB_DIR/log.zsh"
source "$LIB_DIR/safety.zsh"

macadmin_parse_globals "$@" 2>/dev/null || true
if (( ${#MACADMIN_ARGS[@]} > 0 )); then
  set -- "${MACADMIN_ARGS[@]}"
else
  set --
fi
require_macos || exit 1

usage()
{
  cat <<'EOF'
disk.zsh - disk usage helpers

Usage:
  disk.zsh largest   [--path <root>] [--limit N] [--json|--pretty]
  disk.zsh duplicates [--path <root>] [--delete] [--yes] [--protect]
                      [--json|--pretty]
  disk.zsh help

Subcommands:
  largest    List the largest directories under <root> (default: $HOME),
             sorted by disk usage descending. Uses `du -sk`; respects
             junk-dir pruning.

  duplicates Walk <root> and group files by sha256 hash. With --delete,
             removes duplicates EXCEPT one canonical copy per group.
             --delete requires --yes. Honors MACADMIN_PROTECT gate.

Flags:
  --path <root>   Root directory to scan (default: $HOME).
  --limit N       Show at most N results (default: 20 for largest).
  --json          Compact JSON output (one object per line).
  --pretty        Pretty-printed JSON output.
  --delete        (duplicates) Remove duplicates. Requires --yes.
  --yes           Confirm destructive operations.
  --protect       Refuse destructive operations even with --yes.
  --dry-run       Print planned actions without executing.

Notes:
  - 'duplicates' hashes every file under <root>; on a large home
    directory this can take minutes. Use a subpath for quick scans.
  - 'largest' skips: .git, node_modules, __pycache__, .tox, site-packages,
    Library/Caches, Library/Application Support.
EOF
}

# Pretty-print a byte count (reused by both subcommands).
_disk_human_size()
{
  local b=$1
  if (( b >= 1073741824 )); then
    print -r -- "$((b / 1073741824 )).$(( (b % 1073741824) * 10 / 1073741824 ))G"
  elif (( b >= 1048576 )); then
    print -r -- "$((b / 1048576 )).$(( (b % 1048576) * 10 / 1048576 ))M"
  elif (( b >= 1024 )); then
    print -r -- "$((b / 1024 ))K"
  else
    print -r -- "${b}B"
  fi
}

# --- largest subcommand ---

_disk_largest()
{
  local root="$HOME"
  local limit=20
  local pretty=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --path)
        (( $# >= 2 )) || { print -r -- "[ERROR] --path requires a value" >&2; exit ${EX_USAGE:-64}; }
        root="$2"; shift 2 ;;
      --limit)
        (( $# >= 2 )) || { print -r -- "[ERROR] --limit requires a value" >&2; exit ${EX_USAGE:-64}; }
        limit="$2"; shift 2 ;;
      --pretty) pretty=1; shift ;;
      --json|--quiet|--verbose|--dry-run|--yes|--protect) shift ;;
      --) shift; break ;;
      -*) print -r -- "[ERROR] largest: unknown flag: $1" >&2; exit ${EX_USAGE:-64} ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "$root" ]]; then
    print -r -- "[ERROR] largest: path not found: $root" >&2
    exit ${EX_NOINPUT:-66}
  fi
  root="${root:A}"

  # `du -sk <dir>` recursively reports size in 1024-byte blocks. Stream
  # the top-level entries under <root> (not <root> itself).
  # Use `find -E` with prune to skip known noise.
  local raw
  raw=$(find -E "$root" -type d \( \
        -name '.git' -o -name 'node_modules' -o -name '__pycache__' -o \
        -name '.tox' -o -name '.pytest_cache' -o -name '.mypy_cache' -o \
        -name 'site-packages' -o -name 'Library' \
      \) -prune -o -type d -depth 1 -print 2>/dev/null \
      | while IFS= read -r d; do
          [[ -z "$d" || "$d" == "$root" ]] && continue
          local sz_kb
          sz_kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
          : "${sz_kb:=0}"
          print -r -- "${sz_kb}"$'\t'"$d"
        done \
      | sort -t $'\t' -k1 -n -r)

  # Apply --limit.
  local lines
  lines=$(print -r -- "$raw" | head -n "$limit")

  if ((MACADMIN_JSON)) || ((pretty)); then
    local first=1
    ((pretty)) && printf '[\n'
    while IFS=$'\t' read -r sz_kb path; do
      [[ -z "$path" ]] && continue
      local sz_b=$(( sz_kb * 1024 ))
      if ((pretty)); then
        ((first)) || printf ',\n'
        printf '  '
        macadmin_json_pretty_obj path="$path" size_bytes="$sz_b" size_kb="$sz_kb"
        first=0
      else
        macadmin_json_obj path="$path" size_bytes="$sz_b" size_kb="$sz_kb"
        printf '\n'
      fi
    done <<<"$lines"
    ((pretty)) && printf '\n]\n'
  else
    printf '%12s  %s\n' SIZE_KB PATH
    while IFS=$'\t' read -r sz_kb path; do
      [[ -z "$path" ]] && continue
      local hsz="$(_disk_human_size $((sz_kb * 1024)))"
      printf '%12s  %s\n' "$hsz" "$path"
    done <<<"$lines"
  fi
}

# --- duplicates subcommand ---

# Hash a file by sha256 (prefer shasum -a 256; fall back to sha256sum).
_disk_sha256_file()
{
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  else
    print -r -- ""
    return 1
  fi
}

_disk_duplicates()
{
  local root="$HOME"
  local do_delete=0
  local pretty=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --path)
        (( $# >= 2 )) || { print -r -- "[ERROR] --path requires a value" >&2; exit ${EX_USAGE:-64}; }
        root="$2"; shift 2 ;;
      --delete) do_delete=1; shift ;;
      --pretty) pretty=1; shift ;;
      --json|--quiet|--verbose|--dry-run|--yes|--protect) shift ;;
      --) shift; break ;;
      -*) print -r -- "[ERROR] duplicates: unknown flag: $1" >&2; exit ${EX_USAGE:-64} ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "$root" ]]; then
    print -r -- "[ERROR] duplicates: path not found: $root" >&2
    exit ${EX_NOINPUT:-66}
  fi
  root="${root:A}"

  # --delete safety gate: --protect blocks --delete unconditionally
  # (consistent with macadmin_safety_protect_gate semantics). Otherwise
  # --yes is required.
  if (( do_delete )); then
    if (( MACADMIN_PROTECT )); then
      print -r -- "[ERROR] duplicates: --protect blocks --delete (unset MACADMIN_PROTECT to allow)" >&2
      exit ${EX_NOPERM:-77}
    fi
    if (( ! MACADMIN_YES )); then
      print -r -- "[ERROR] duplicates: --delete requires --yes (use --dry-run to preview)" >&2
      exit ${EX_NOPERM:-77}
    fi
  fi

  log_info "Hashing files under $root (this may take a while)..."
  # Walk every regular file; emit hash<TAB>path.
  local hashed
  hashed=$(find "$root" -type f -print 2>/dev/null | while IFS= read -r f; do
    local h
    h="$(_disk_sha256_file "$f")"
    [[ -z "$h" ]] && continue
    print -r -- "${h}"$'\t'"$f"
  done)

  # Group by hash: lines with same hash -> dupes. Sort so identical
  # hashes cluster.
  local grouped
  grouped=$(print -r -- "$hashed" | sort -t $'\t' -k1,1)

  # Collapse: emit one group header per duplicate hash (>= 2 paths).
  # Track count and emit groups.
  local last_hash=""
  local -a group_paths=()
  local -a emit_lines=()  # "hash<TAB>path" pairs for duplicates

  while IFS=$'\t' read -r h p; do
    [[ -z "$h" || -z "$p" ]] && continue
    if [[ "$h" == "$last_hash" ]]; then
      group_paths+=("$p")
    else
      # Flush previous group if it had >=2 paths.
      if (( ${#group_paths[@]} >= 2 )); then
        local gpath
        for gpath in "${group_paths[@]}"; do
          emit_lines+=("${last_hash}"$'\t'"$gpath")
        done
      fi
      group_paths=("$p")
      last_hash="$h"
    fi
  done <<<"$grouped"
  # Trailing group.
  if (( ${#group_paths[@]} >= 2 )); then
    local gpath
    for gpath in "${group_paths[@]}"; do
      emit_lines+=("${last_hash}"$'\t'"$gpath")
    done
  fi

  if (( ${#emit_lines[@]} == 0 )); then
    log_info "No duplicates found."
    if ((MACADMIN_JSON)); then printf '[]\n'
    elif ((pretty)); then printf '[]\n'; fi
    return 0
  fi

  # Group by hash for deletion: keep first, delete rest. Extracted to a
  # function to avoid `local x; x=$(...)` in loop scope (zsh quirk).
  local -a to_delete=()
  to_delete=("$(_disk_duplicates_pick_deletions "${emit_lines[@]}")")

  if ((MACADMIN_JSON)) || ((pretty)); then
    ((pretty)) && printf '[\n'
    local first=1
    local l h p sz_b
    for l in "${emit_lines[@]}"; do
      h="${l%%$'\t'*}"
      p="${l#*$'\t'}"
      sz_b=$(stat -f %z "$p" 2>/dev/null || echo 0)
      if ((pretty)); then
        ((first)) || printf ',\n'
        printf '  '
        macadmin_json_pretty_obj hash="$h" path="$p" size_bytes="$sz_b"
        first=0
      else
        macadmin_json_obj hash="$h" path="$p" size_bytes="$sz_b"
        printf '\n'
      fi
    done
    ((pretty)) && printf '\n]\n'
  else
    printf '%s  %s\n' HASH PATH
    for l in "${emit_lines[@]}"; do
      h="${l%%$'\t'*}"
      p="${l#*$'\t'}"
      sz_b=$(stat -f %z "$p" 2>/dev/null || echo 0)
      printf '%s  %s  (%s)\n' "$h" "$p" "$(_disk_human_size "$sz_b")"
    done
  fi

  if (( do_delete )); then
    log_info "Deleting ${#to_delete[@]} duplicate file(s) (keeping first per group)..."
    local d
    for d in "${to_delete[@]}"; do
      rm -f -- "$d" 2>/dev/null && log_info "deleted: $d"
    done
  fi
}

# From a list of "hash<TAB>path" lines (already sorted by hash), emit
# the paths to KEEP-AND-NOT-DELETE (first per group). Echoed to stdout.
# Wait: we want the paths to DELETE (skip first per group). Echoes
# one path per line; caller joins into an array.
#
# Implemented in a function so the per-iteration `local x; x=$(...)`
# pattern is contained in function scope (which doesn't echo at end).
_disk_duplicates_pick_deletions()
{
  emulate -L zsh
  local cur_hash=""
  local line h p
  for line in "$@"; do
    h="${line%%$'\t'*}"
    p="${line#*$'\t'}"
    if [[ "$h" == "$cur_hash" ]]; then
      print -r -- "$p"
    else
      cur_hash="$h"
    fi
  done
}

# --- dispatcher ---

subcmd=${1:-}
case "$subcmd" in
  ""|-h|--help|help) usage; exit 0 ;;
  largest) shift; _disk_largest "$@" ;;
  duplicates) shift; _disk_duplicates "$@" ;;
  *)
    print -r -- "[ERROR] disk: unknown subcommand: ${subcmd:-<none>}" >&2
    usage >&2
    exit ${EX_USAGE:-64}
    ;;
esac

exit ${EX_OK:-0}
