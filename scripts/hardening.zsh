#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
require_macos || exit 1

usage() {
  cat <<'EOF'
hardening.zsh - basic macOS security hardening

Usage:
  hardening.zsh status
  hardening.zsh firewall on|off
  hardening.zsh gatekeeper on|off

Notes:
  - Some changes require admin rights and/or reboot.
  - FileVault enablement is intentionally not automated here.
EOF
}

status() {
  log_info "Firewall"
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate || true
  log_info "Gatekeeper"
  spctl --status || true
  log_info "SIP (System Integrity Protection)"
  csrutil status 2>/dev/null || echo "Query requires Recovery context on some versions."
  log_info "FileVault"
  fdesetup status 2>/dev/null || true
}

cmd=${1:-}
case "$cmd" in
  status)
    status
    ;;
  firewall)
    action=${2:-}
    require_sudo
    case "$action" in
      on)  log_info "Enabling firewall..."; run sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on ;;
      off) log_info "Disabling firewall..."; run sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off ;;
      *) usage; exit 1 ;;
    esac
    ;;
  gatekeeper)
    action=${2:-}
    require_sudo
    case "$action" in
      on)  log_info "Enabling Gatekeeper..."; run sudo spctl --master-enable ;;
      off) log_info "Disabling Gatekeeper..."; run sudo spctl --master-disable ;;
      *) usage; exit 1 ;;
    esac
    ;;
  -h|--help|*) usage; exit 0 ;;
esac

log_info "Done."
