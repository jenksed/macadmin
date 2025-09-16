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
network.zsh - network helpers for macOS

Usage:
  network.zsh services
  network.zsh wifi on|off
  network.zsh dns-flush

Examples:
  network.zsh services
  network.zsh wifi off
  network.zsh dns-flush
EOF
}

cmd=${1:-}
case "$cmd" in
  services)
    log_info "Listing network services..."
    networksetup -listallnetworkservices || die "networksetup failed"
    ;;
  wifi)
    action=${2:-}
    [[ -z "$action" ]] && { usage; exit 1; }
    # Find Wi-Fi device name
    local port dev
    port=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{f=1} f && /Device/{print $2; exit}')
    dev=$port
    if [[ -z "$dev" ]]; then die "Wi‑Fi device not found"; fi
    case "$action" in
      on)  log_info "Enabling Wi‑Fi on $dev"; run networksetup -setairportpower "$dev" on ;;
      off) log_info "Disabling Wi‑Fi on $dev"; run networksetup -setairportpower "$dev" off ;;
      *) usage; exit 1 ;;
    esac
    ;;
  dns-flush)
    require_sudo
    log_info "Flushing DNS cache..."
    run sudo dscacheutil -flushcache
    run sudo killall -HUP mDNSResponder || true
    ;;
  -h|--help|*) usage; exit 0 ;;
esac

log_info "Done."
