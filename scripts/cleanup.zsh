#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
# cleanup.zsh - safely clear user/system caches and logs (allowlisted)
#
# Release 0.3 changes:
#   - Sources lib/{common,argparse,exitcodes,log,safety,paths}.zsh
#   - Uses lib/safety.zsh ignore-pattern matching (fixes the local
#     pattern loop that was a duplicate and broken)
#   - Uses lib/paths.zsh cache root accessors
#   - Adds --json and --pretty output
#   - Adds --older-than <days> and --larger-than <size> filters
#   - Honors MACADMIN_PROTECT gate
#   - Fixes the empty MACADMIN_ARGS guard
#   - Replaces local _within_any / _should_ignore helpers with library
#     equivalents (macadmin_safety_within / macadmin_safety_ignored)

emulate -L zsh
set -o errexit -o nounset -o pipefail

SCRIPT_DIR=${0:a:h}
REPO_DIR=${SCRIPT_DIR:h}
LIB_DIR="$REPO_DIR/lib"

source "$LIB_DIR/common.zsh"
source "$LIB_DIR/argparse.zsh"
source "$LIB_DIR/exitcodes.zsh"
source "$LIB_DIR/log.zsh"
source "$LIB_DIR/paths.zsh"
source "$LIB_DIR/safety.zsh"

# Parse global flags. Guard against empty array (zsh quirk).
macadmin_parse_globals "$@" 2>/dev/null || true
if (( ${#MACADMIN_ARGS[@]} > 0 )); then
  set -- "${MACADMIN_ARGS[@]}"
else
  set --
fi
require_macos || exit ${EX_OSERR:-71}

usage() {
  cat <<'EOF'
cleanup.zsh - safely clear user/system caches and logs (allowlisted)

Usage:
  cleanup.zsh [--user] [--system] [--older-than <days>] [--larger-than <size>]
              [--dry-run] [--yes] [--protect] [--json] [--pretty] [-h|--help]

Flags:
  --user               Clean user caches/logs and safe dev caches
  --system             Clean system caches in /Library/Caches (sudo)
  --older-than <days>  Only delete entries older than <days>
  --larger-than <size> Only delete entries larger than <size>
  --dry-run            Print a plan of actions without executing
  --yes                Confirm deletion (required for destructive actions)
  --protect            Extra safety guard; refuse without --yes
  --json               Emit JSON events instead of human output
  --pretty             Pretty-print JSON

Notes:
  - Deletes only within a strict allowlist of roots.
  - Honors patterns in ~/.macadminignore; skipped paths are printed.
  - Honors MACADMIN_PROTECT gate.

Examples:
  cleanup.zsh --user --dry-run
  cleanup.zsh --user --yes
  cleanup.zsh --system --older-than 30 --dry-run
  cleanup.zsh --user --json | jq -r '.event'
EOF
}

typeset -i opt_user=0 opt_system=0 opt_older=0 opt_larger=0
typeset -i opt_json=${MACADMIN_JSON:-0} opt_pretty=0
typeset -i opt_protect=${MACADMIN_PROTECT:-0}
typeset -i opt_dry_run=${MACADMIN_DRY_RUN:-0}
typeset -i opt_yes=${MACADMIN_YES:-0}
opt_older_days=0
opt_larger_bytes=0

# Two-pass parse so --flag value pairs work cleanly.
typeset -a _args
_args=("$@")
typeset -i _i=1
typeset -i _expect_value=0
while (( _i <= ${#_args[@]} )); do
  local arg="${_args[_i]}"
  if (( _expect_value )); then
    if [[ "$arg" == "--older-than" || "$arg" == "--larger-than" || "$arg" == --* ]]; then
      log_error "--${_args[_i-1]#--} requires a value"
      exit ${EX_USAGE:-64}
    fi
    case "${_args[_i-1]}" in
      --older-than) opt_older=1; opt_older_days="$arg" ;;
      --larger-than) opt_larger=1; opt_larger_bytes="$arg" ;;
    esac
    _expect_value=0
    (( _i++ ))
    continue
  fi
  case "$arg" in
    -h|--help) usage; exit ${EX_OK:-0} ;;
    --user) opt_user=1 ;;
    --system) opt_system=1 ;;
    --older-than) _expect_value=1 ;;
    --older-than=*)
      opt_older=1
      opt_older_days=${arg#*=}
      ;;
    --larger-than) _expect_value=1 ;;
    --larger-than=*)
      opt_larger=1
      opt_larger_bytes=${arg#*=}
      ;;
    --dry-run) opt_dry_run=1 ;;
    --yes) opt_yes=1 ;;
    --protect) opt_protect=1 ;;
    --json) opt_json=1 ;;
    --pretty) opt_pretty=1 ;;
    *)
      log_error "unknown arg: $arg"
      usage >&2
      exit ${EX_USAGE:-64}
      ;;
  esac
  (( _i++ ))
done

# Parse size string (e.g., "10M", "1G") into bytes.
_parse_size() {
  local s="$1"
  local last multiplier=1
  last=${s: -1}
  case "$last" in
    K|k) multiplier=1024 ;;
    M|m) multiplier=1048576 ;;
    G|g) multiplier=1073741824 ;;
    *) multiplier=1 ;;
  esac
  if [[ "$last" == [KMGkmg] ]]; then
    print -r -- $(( ${s%?} * multiplier ))
  else
    print -r -- $(( s * multiplier ))
  fi
}

if (( opt_larger )); then
  opt_larger_bytes=$(_parse_size "$opt_larger_bytes")
fi

if (( ! opt_user && ! opt_system )); then
  usage >&2
  exit ${EX_USAGE:-64}
fi

# Load ignore patterns and build allowlist.
macadmin_safety_load_ignore

typeset -ga USER_ROOTS=()
typeset -ga SYSTEM_ROOTS=()

if (( opt_user )); then
  USER_ROOTS+=(
    "$(macadmin_path_user_cache)"
    "$(macadmin_path_user_logs)"
    "$(macadmin_path_xcode_derived_data)"
    "$(macadmin_path_npm_cache)"
    "$(macadmin_path_yarn_cache_v6)"
    "$(macadmin_path_yarn_cache)"
    "$(macadmin_path_docker_logs)"
    "${HOME}/Library/Containers/com.docker.docker/Data/diagnostics"
  )
fi
if (( opt_system )); then
  SYSTEM_ROOTS+=("$(macadmin_path_system_cache)")
fi

typeset -ga ALLOW_ROOTS=("${USER_ROOTS[@]}" "${SYSTEM_ROOTS[@]}")
typeset -ga PLAN_DELETE=()
typeset -ga PLAN_KEEP=()
typeset -ga PLAN_SKIP_REASON=()

_path_abs() { print -r -- "${1:A}"; }

_path_age_days() {
  local p="$1"
  [[ -e "$p" ]] || { print -r -- "-1"; return; }
  local mtime now
  mtime=$(stat -f '%m' "$p" 2>/dev/null || print -r -- "0")
  now=$(date +%s)
  print -r -- $(( (now - mtime) / 86400 ))
}

_path_size_bytes() {
  local p="$1"
  [[ -d "$p" ]] || { print -r -- "0"; return; }
  du -sk "$p" 2>/dev/null | awk '{print $1 * 1024}'
}

_passes_filters() {
  local p="$1"
  if (( opt_older )); then
    local age
    age=$(_path_age_days "$p")
    (( age >= opt_older_days )) || return 1
  fi
  if (( opt_larger )); then
    local sz
    sz=$(_path_size_bytes "$p")
    (( sz >= opt_larger_bytes )) || return 1
  fi
  return 0
}

_plan_for_root() {
  local root="$1"
  local absroot
  absroot=$(_path_abs "$root")
  [[ -d "$absroot" ]] || return 0
  local e
  for e in "$absroot"/*(N); do
    if macadmin_safety_ignored "$e"; then
      PLAN_KEEP+=("$e")
      PLAN_SKIP_REASON+=("ignored")
      continue
    fi
    if ! macadmin_safety_within "$e" "${ALLOW_ROOTS[@]}"; then
      PLAN_KEEP+=("$e")
      PLAN_SKIP_REASON+=("outside-allowlist")
      continue
    fi
    if ! _passes_filters "$e"; then
      PLAN_KEEP+=("$e")
      PLAN_SKIP_REASON+=("filtered")
      continue
    fi
    PLAN_DELETE+=("$e")
  done
}

for r in "${ALLOW_ROOTS[@]}"; do _plan_for_root "$r"; done

if (( opt_json )); then
  if (( opt_pretty )); then
    print -r -- "{"
    print -r -- "  \"event\": \"cleanup_plan\","
    print -r -- "  \"dry_run\": $( ((opt_dry_run)) && echo true || echo false ),"
    print -r -- "  \"user\": $( ((opt_user)) && echo true || echo false ),"
    print -r -- "  \"system\": $( ((opt_system)) && echo true || echo false ),"
    print -r -- "  \"to_delete\": ["
    typeset -i _ar=0
    for p in "${PLAN_DELETE[@]}"; do
      (( _ar > 0 )) && print -r -- ","
      print -r -- "    \"$p\""
      (( _ar++ ))
    done
    print -r -- "  ],"
    print -r -- "  \"to_keep\": ["
    typeset -i _k=0
    typeset -i _i2=0
    for p in "${PLAN_KEEP[@]}"; do
      (( _k > 0 )) && print -r -- ","
      print -r -- "    {\"path\":\"$p\",\"reason\":\"${PLAN_SKIP_REASON[_i2]}\"}"
      (( _k++ ))
      (( _i2++ ))
    done
    print -r -- "  ]"
    print -r -- "}"
  else
    print -rn -- "{\"event\":\"cleanup_plan\",\"dry_run\":"
    (( opt_dry_run )) && print -rn -- "true" || print -rn -- "false"
    print -rn -- ",\"user\":"
    (( opt_user )) && print -rn -- "true" || print -rn -- "false"
    print -rn -- ",\"system\":"
    (( opt_system )) && print -rn -- "true" || print -rn -- "false"
    print -rn -- ",\"to_delete\":["
    typeset -i _d=0
    for p in "${PLAN_DELETE[@]}"; do
      (( _d > 0 )) && print -rn -- ","
      print -rn -- "\"$p\""
      (( _d++ ))
    done
    print -rn -- "],\"to_keep\":["
    typeset -i _k=0
    typeset -i _i2=0
    for p in "${PLAN_KEEP[@]}"; do
      (( _k > 0 )) && print -rn -- ","
      print -rn -- "{\"path\":\"$p\",\"reason\":\"${PLAN_SKIP_REASON[_i2]}\"}"
      (( _k++ ))
      (( _i2++ ))
    done
    print -rn -- "]}"
    print -r -- ""
  fi
else
  if (( opt_user )); then log_info "Cleaning user caches..."; fi
  if (( opt_system )); then log_info "Cleaning system caches..."; fi

  if (( ${#PLAN_DELETE[@]} == 0 )); then
    log_info "No matching cache entries found to delete."
  else
    log_info "Planned deletions (${#PLAN_DELETE[@]} items):"
    local p
    for p in "${PLAN_DELETE[@]}"; do
      print -r -- "  PLAN delete: $p"
    done
  fi

  if (( ${#PLAN_KEEP[@]} > 0 )); then
    log_info "Kept by ignore/filter (${#PLAN_KEEP[@]} items):"
    local i=1
    while (( i <= ${#PLAN_KEEP[@]} )); do
      print -r -- "  KEEP: ${PLAN_KEEP[i]}  (reason: ${PLAN_SKIP_REASON[i]})"
      (( i++ ))
    done
  fi
fi

if (( opt_dry_run )); then
  if (( ! opt_json )); then
    log_info "Dry-run mode: no changes made."
    log_info "Cleanup complete."
  fi
  exit ${EX_OK:-0}
fi

if (( ${#PLAN_DELETE[@]} > 0 )); then
  if (( opt_protect )) && (( ! opt_yes )); then
    if (( ! opt_json )); then
      log_error "refusing to mutate under --protect without --yes"
    fi
    exit ${EX_NOPERM:-77}
  fi
  if (( ! opt_yes )); then
    if (( ! opt_json )); then
      log_error "Refusing to delete without --yes. Re-run with --dry-run to preview."
    fi
    exit ${EX_NOPERM:-77}
  fi
fi

if (( opt_system )); then require_sudo; fi

local d
for d in "${PLAN_DELETE[@]}"; do
  if ! macadmin_safety_within "$d" "${ALLOW_ROOTS[@]}"; then
    log_warn "Refusing to remove outside allowlist: $d"
    continue
  fi
  if (( opt_json )); then
    print -r -- "{\"event\":\"cleanup_delete\",\"path\":\"$d\"}"
  else
    log_info "Deleting: $d"
  fi
  if (( opt_system )); then
    run sudo rm -rf -- "$d"
  else
    run rm -rf -- "$d"
  fi
done

if (( ! opt_json )); then
  log_info "Cleanup complete."
fi

exit ${EX_OK:-0}