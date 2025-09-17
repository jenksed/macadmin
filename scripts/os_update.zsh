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
os_update.zsh - list and install macOS updates (softwareupdate wrapper)

Usage:
  os_update.zsh --list
  os_update.zsh --install <label|all> [--restart] [--dry-run] [--yes]

Flags:
  --list           List available updates (passes through upstream output)
  --install ARG    Install a specific update label or 'all'
  --restart        Allow automatic restart if required (with --install)
  --dry-run        Print planned actions without executing
  --yes            Confirm installation (required for --install)

Notes:
  - Safe-by-default: --install requires --yes unless --dry-run.
  - If any selected updates require restart but --restart is not set, exits non-zero with a clear message.
  - Labels are parsed from `softwareupdate --list` output.

Examples:
  os_update.zsh --list
  os_update.zsh --install all --dry-run
  os_update.zsh --install MockUpdate-1 --yes --restart
EOF
}

typeset -i opt_list=0 opt_restart=0
typeset opt_install=""

# Parse command-specific flags (globals already stripped)
typeset -i i=1
while (( i <= ARGC )); do
  case "${argv[i]}" in
    --list) opt_list=1 ;;
    --restart) opt_restart=1 ;;
    --install)
      (( i++ )) || true
      if (( i <= ARGC )); then
        opt_install="${argv[i]}"
      else
        log_error "--install requires a value (label or 'all')"
        usage; exit ${EX_USAGE:-64}
      fi
      ;;
    --install=*) opt_install="${argv[i]#--install=}" ;;
    -h|--help) usage; exit 0 ;;
    --dry-run|--yes|--verbose|--json|--quiet|--protect) : ;;
    *) log_warn "Unknown arg: ${argv[i]}"; usage; exit ${EX_USAGE:-64} ;;
  esac
  (( i++ ))
done

require_cmd softwareupdate || exit ${EX_UNAVAILABLE:-69}

# Helpers to inspect available updates
_su_list_output() {
  # Capture list output without exiting on upstream non-zero
  softwareupdate --list 2>&1 || true
}

_parse_labels() {
  # stdin: softwareupdate --list output
  # out: one label per line
  awk '/^\* Label:/ { sub(/^\* Label:[[:space:]]*/, ""); print }'
}

_label_block_contains_restart() {
  # $1: label; stdin: softwareupdate --list output
  # exit 0 if block for label contains a restart hint
  awk -v target="$1" '
    BEGIN { cur=""; inblk=0; found=0 }
    /^\* Label:/ {
      cur=$0; sub(/^\* Label:[[:space:]]*/, "", cur);
      inblk = (cur == target)
      next
    }
    inblk {
      if (tolower($0) ~ /restart/) { found=1 }
    }
    END { exit(found?0:1) }'
}

_any_selected_require_restart() {
  # $1: selection type: 'all' or label; $2: list output blob
  local sel="$1" blob="$2"
  if [[ "$sel" == all ]]; then
    print -r -- "$blob" | awk 'BEGIN{f=0} tolower($0) ~ /restart/ {f=1} END{exit(f?0:1)}'
    return $?
  fi
  print -r -- "$blob" | _label_block_contains_restart "$sel"
}

_label_exists() {
  # $1: label; $2: list output blob
  print -r -- "$2" | _parse_labels | grep -Fx -- "$1" >/dev/null 2>&1
}

if (( opt_list )); then
  log_info "Listing available updates..."
  # Pass-through for human-friendly details
  run softwareupdate --list

  # Additionally, parse labels for quick reference
  if (( ! MACADMIN_JSON )); then
    labels=()
    labels=($( _su_list_output | _parse_labels )) || labels=()
    if (( ${#labels[@]} > 0 )); then
      print -r -- "Labels: ${labels[*]}"
    else
      log_info "No updates found."
    fi
  fi
fi

if [[ -n "$opt_install" ]]; then
  # Safety-by-default
  if (( ! MACADMIN_DRY_RUN )) && (( ! MACADMIN_YES )); then
    log_error "Refusing to install updates without --yes. Re-run with --dry-run to preview."
    exit ${EX_NOPERM:-77}
  fi

  # Determine availability and restart requirements
  list_blob=$(_su_list_output)
  labels_avail=($( print -r -- "$list_blob" | _parse_labels )) || labels_avail=()

  if [[ "$opt_install" == all ]]; then
    if (( ${#labels_avail[@]} == 0 )); then
      log_info "No updates available."
      exit 0
    fi
  else
    if ! _label_exists "$opt_install" "$list_blob"; then
      log_error "Label not found among available updates: $opt_install"
      exit ${EX_UNAVAILABLE:-69}
    fi
  fi

  if _any_selected_require_restart "$opt_install" "$list_blob"; then
    if (( ! opt_restart )); then
      log_error "One or more selected updates require a restart. Re-run with --restart to proceed."
      exit ${EX_TEMPFAIL:-75}
    fi
  fi

  # Build command
  typeset -a cmd
  cmd=(softwareupdate --install)
  if [[ "$opt_install" == all ]]; then
    cmd+=(--all)
  else
    cmd+=("$opt_install")
  fi
  (( opt_restart )) && cmd+=(--restart)

  if (( MACADMIN_DRY_RUN )); then
    log_info "Dry-run: planned install command: ${(q)cmd}"
    exit 0
  fi

  require_sudo
  log_info "Installing updates (target: $opt_install)..."
  run sudo "$cmd[@]"
  exit 0
fi

if (( ! opt_list )) ; then
  usage; exit ${EX_USAGE:-64}
fi
