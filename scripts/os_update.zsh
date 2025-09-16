#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
require_macos || exit 1

usage() {
  cat <<'EOF'
os_update.zsh - manage macOS software updates

Usage:
  os_update.zsh --list
  os_update.zsh --install [--restart]

Flags:
  --list      List available updates
  --install   Install all available updates
  --restart   Restart automatically if required (with --install)
  --dry-run   Print actions without executing
EOF
}

list=0 install=0 restart=0
for arg in "$@"; do
  case "$arg" in
    --list) list=1 ;;
    --install) install=1 ;;
    --restart) restart=1 ;;
    --dry-run) export DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) log_warn "Unknown arg: $arg"; usage; exit 1 ;;
  esac
done

require_cmd softwareupdate || exit 1

if (( list )); then
  log_info "Listing available updates..."
  run softwareupdate --list
fi

if (( install )); then
  require_sudo
  log_info "Installing all available updates..."
  if (( restart )); then
    run sudo softwareupdate --install --all --restart
  else
    run sudo softwareupdate --install --all
  fi
fi

if (( ! list && ! install )); then
  usage; exit 1
fi

log_info "Done."
