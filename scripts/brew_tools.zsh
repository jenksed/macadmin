#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
require_macos || exit 1

usage() {
  cat <<'EOF'
brew_tools.zsh - Homebrew helpers

Usage:
  brew_tools.zsh check
  brew_tools.zsh ensure
  brew_tools.zsh bundle [--file Brewfile]

Notes:
  - 'ensure' installs Homebrew if missing (interactive).
  - 'bundle' runs `brew bundle` in current dir (or --file path).
EOF
}

cmd=${1:-}
case "$cmd" in
  check)
    if command -v brew >/dev/null 2>&1; then
      log_info "Homebrew found: $(brew --version | head -1)"
    else
      log_warn "Homebrew not installed."
      return 1
    fi
    ;;
  ensure)
    if command -v brew >/dev/null 2>&1; then
      log_info "Homebrew already installed."
    else
      log_info "Installing Homebrew (will prompt)..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    ;;
  bundle)
    require_cmd brew || exit 1
    fileflag=()
    if [[ ${2:-} == "--file" && -n ${3:-} ]]; then
      fileflag=(--file "$3")
    fi
    log_info "Running brew bundle ${fileflag:+with file ${fileflag[2]}}..."
    run brew bundle $fileflag
    ;;
  -h|--help|*) usage; exit 0 ;;
esac

log_info "Done."
