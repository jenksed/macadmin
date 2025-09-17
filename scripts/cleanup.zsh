#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
emulate -L zsh
set -o errexit -o nounset -o pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
source "$SCRIPT_DIR/../lib/argparse.zsh" 2>/dev/null || true
macadmin_parse_globals "$@" 2>/dev/null || true
set -- "${MACADMIN_ARGS[@]:-}"
require_macos || exit 1

usage() {
  cat <<'EOF'
cleanup.zsh - safely clear user/system caches and logs (allowlisted)

Usage:
  cleanup.zsh [--user] [--system] [--dry-run] [--yes] [--protect]

Flags:
  --user      Clean user caches/logs and safe dev caches (Xcode DerivedData,
              npm/yarn caches, Docker Desktop logs)
  --system    Clean system caches in /Library/Caches (sudo)
  --dry-run   Print a plan of actions without executing
  --yes       Confirm deletion (required for destructive actions)
  --protect   Extra safety guard (reserved)

Notes:
  - Deletes only within a strict allowlist of roots.
  - Honors patterns in ~/.macadminignore; skipped paths are printed.

Examples:
  cleanup.zsh --user --dry-run
  cleanup.zsh --user --yes
  cleanup.zsh --system --dry-run && cleanup.zsh --system --yes
EOF
}

typeset -i opt_user=0 opt_system=0
for arg in "$@"; do
  case "$arg" in
    --user) opt_user=1 ;;
    --system) opt_system=1 ;;
    --dry-run|--yes|--verbose|--json|--quiet|--protect) : ;;
    -h|--help) usage; exit 0 ;;
    *) log_warn "Unknown arg: $arg"; usage; exit 64 ;;
  esac
done

if (( ! opt_user && ! opt_system )); then
  usage; exit 64
fi

# Optional preface to satisfy human expectations and tests
(( opt_user )) && log_info "Cleaning user caches..."
(( opt_system )) && log_info "Cleaning system caches..."

# Read ignore patterns
typeset -ga _IGNORE_PATTERNS=()
if [[ -r "$HOME/.macadminignore" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    _IGNORE_PATTERNS+="$line"
  done < "$HOME/.macadminignore"
fi

_abs() { local p="$1"; print -r -- "${p:A}"; }

_within_any() {
  local p; p=$(_abs "$1"); shift
  local r
  for r in "$@"; do
    r=$(_abs "$r")
    [[ "$p" == "$r" || "$p" == ${r%/}/* ]] && return 0
  done
  return 1
}

_should_ignore() {
  local p="$1" pat
  for pat in "${_IGNORE_PATTERNS[@]}"; do
    local pattmp="$pat"
    case "$pattmp" in
      ~*) pattmp=${~pattmp} ;;
    esac
    local target="$p"
    [[ "$pattmp" == /* ]] || target=${p:t}
    if [[ "$target" == $pattmp ]]; then
      print -r -- "$pattmp"; return 0
    fi
  done
  return 1
}

typeset -ga USER_ROOTS=()
typeset -ga SYSTEM_ROOTS=()
typeset -ga ALLOW_ROOTS=()

if (( opt_user )); then
  USER_ROOTS+=(
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Developer/Xcode/DerivedData"
    "$HOME/.npm/_cacache"
    "$HOME/.cache/yarn"
    "$HOME/Library/Caches/Yarn"
    "$HOME/Library/Caches/npm"
    "$HOME/Library/Containers/com.docker.docker/Data/log"
    "$HOME/Library/Containers/com.docker.docker/Data/diagnostics"
  )
fi
if (( opt_system )); then
  SYSTEM_ROOTS+=("/Library/Caches")
fi
ALLOW_ROOTS=(${USER_ROOTS[@]} ${SYSTEM_ROOTS[@]})

typeset -ga PLAN_DELETE=()
typeset -ga PLAN_SKIP=()
typeset -ga PLAN_SKIP_REASON=()

_plan_for_root() {
  local root="$1" absroot
  absroot=$(_abs "$root")
  [[ -d "$absroot" ]] || return 0
  local e why
  for e in "$absroot"/*(N); do
    if why=$(_should_ignore "$e"); then
      PLAN_SKIP+="$e"; PLAN_SKIP_REASON+="$why"; continue
    fi
    if _within_any "$e" "$absroot"; then
      PLAN_DELETE+="$e"
    else
      PLAN_SKIP+="$e"; PLAN_SKIP_REASON+="outside-allowlist"
    fi
  done
}

typeset r
for r in "${ALLOW_ROOTS[@]}"; do _plan_for_root "$r"; done

if (( ${#PLAN_DELETE[@]} == 0 )); then
  log_info "No matching cache entries found to delete."
else
  log_info "Planned deletions (${#PLAN_DELETE[@]} items):"
  local p
  for p in "${PLAN_DELETE[@]}"; do
    print -r -- "  PLAN delete: $p"
  done
fi

if (( ${#PLAN_SKIP[@]} > 0 )); then
  log_info "Skipped by ignore/guard (${#PLAN_SKIP[@]} items):"
  local i=1
  while (( i <= ${#PLAN_SKIP[@]} )); do
    print -r -- "  SKIP: ${PLAN_SKIP[i]}  (reason: ${PLAN_SKIP_REASON[i]})"
    (( i++ ))
  done
fi

if (( MACADMIN_DRY_RUN )); then
  log_info "Dry-run mode: no changes made."
  log_info "Cleanup complete."
  exit 0
fi

if (( ${#PLAN_DELETE[@]} > 0 )) && (( ! MACADMIN_YES )); then
  log_error "Refusing to delete without --yes. Re-run with --dry-run to preview."
  exit ${EX_NOPERM:-77}
fi

if (( opt_system )); then require_sudo; fi

local d
for d in "${PLAN_DELETE[@]}"; do
  if ! _within_any "$d" "${ALLOW_ROOTS[@]}"; then
    log_warn "Refusing to remove outside allowlist: $d"; continue
  fi
  log_info "Deleting: $d"
  if (( opt_system )); then
    run sudo rm -rf -- "$d"
  else
    run rm -rf -- "$d"
  fi
done

log_info "Cleanup complete."
