#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
source "$SCRIPT_DIR/../lib/argparse.zsh" 2>/dev/null || true
macadmin_parse_globals "$@" 2>/dev/null || true
set -- "${MACADMIN_ARGS[@]}"
require_macos || exit 1

usage() {
  cat <<'EOF'
backup_tmutil.zsh - Time Machine helpers

Usage:
  backup_tmutil.zsh status
  backup_tmutil.zsh start [--auto]
  backup_tmutil.zsh list
  backup_tmutil.zsh thin <percent>
  backup_tmutil.zsh exclude add <path>
  backup_tmutil.zsh exclude remove <path>

Examples:
  backup_tmutil.zsh status
  backup_tmutil.zsh start --auto
  backup_tmutil.zsh thin 20
  backup_tmutil.zsh exclude add ~/Library/Caches
EOF
}

require_cmd tmutil || exit 1

cmd=${1:-}
case "$cmd" in
  status)
    tmutil status || true
    ;;
  start)
    shift || true
    auto=0
    [[ ${1:-} == "--auto" ]] && auto=1
    log_info "Starting Time Machine backup..."
    if (( auto )); then
      run tmutil startbackup --auto
    else
      run tmutil startbackup
    fi
    ;;
  list)
    tmutil listbackups || true
    ;;
  thin)
    percent=${2:-}
    [[ -z "$percent" ]] && { usage; exit 1; }
    require_sudo
    log_info "Thinning local snapshots to ${percent}%..."
    run sudo tmutil thinlocalsnapshots / $percent 4
    ;;
  exclude)
    action=${2:-}
    path=${3:-}
    [[ -z "$action" || -z "$path" ]] && { usage; exit 1; }
    case "$action" in
      add) log_info "Excluding $path"; run tmutil addexclusion "$path" ;;
      remove) log_info "Removing exclusion $path"; run tmutil removeexclusion "$path" ;;
      *) usage; exit 1 ;;
    esac
    ;;
  -h|--help|*) usage; exit 0 ;;
esac

log_info "Done."
