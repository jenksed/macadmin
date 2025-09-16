#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
require_macos || exit 1

usage() {
  cat <<'EOF'
settings_ui.zsh - apply sensible Finder/Dock/Text settings

Usage:
  settings_ui.zsh [--apply] [--restart]

Flags:
  --apply    Apply settings (default if no flags)
  --restart  Restart Finder/Dock to apply immediately
EOF
}

apply=1 restart=0
for arg in "$@"; do
  case "$arg" in
    --apply) apply=1 ;;
    --restart) restart=1 ;;
    -h|--help) usage; exit 0 ;;
    *) log_warn "Unknown arg: $arg"; usage; exit 1 ;;
  esac
done

if (( apply )); then
  log_info "Applying Finder settings..."
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder ShowStatusBar -bool true
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

  log_info "Applying Dock settings..."
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock tilesize -int 48
  defaults write com.apple.dock mineffect -string scale
  defaults write com.apple.dock autohide-delay -float 0

  log_info "Applying input/text settings..."
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
fi

if (( restart )); then
  log_info "Restarting Finder and Dock..."
  killall Finder 2>/dev/null || true
  killall Dock 2>/dev/null || true
fi

log_info "Settings applied."
