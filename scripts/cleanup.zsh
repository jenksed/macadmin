#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
require_macos || exit 1

usage() {
  cat <<'EOF'
cleanup.zsh - clear caches and run maintenance

Usage:
  cleanup.zsh [--user] [--system] [--logs] [--periodic] [--brew] [--dry-run]

Flags:
  --user      Clean user caches in ~/Library/Caches
  --system    Clean system caches in /Library/Caches (sudo)
  --logs      Rotate/compress logs where applicable (sudo)
  --periodic  Run periodic daily/weekly/monthly (sudo)
  --brew      Run 'brew cleanup' if Homebrew is present
  --dry-run   Print actions without executing

Examples:
  cleanup.zsh --user --brew --dry-run
  cleanup.zsh --user --system --logs --periodic
EOF
}

user=0 system=0 logs=0 periodic=0 brew=0
for arg in "$@"; do
  case "$arg" in
    --user) user=1 ;;
    --system) system=1 ;;
    --logs) logs=1 ;;
    --periodic) periodic=1 ;;
    --brew) brew=1 ;;
    --dry-run) export DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown arg: $arg"; usage; exit 1 ;;
  esac
done

(( user || system || logs || periodic || brew )) || { usage; exit 1; }

if (( user )); then
  info "Cleaning user caches..."
  run rm -rf ~/Library/Caches/* 2>/dev/null || true
fi

if (( system )); then
  require_sudo
  if confirm "Clean /Library/Caches (may affect app caches)?"; then
    info "Cleaning system caches..."
    run sudo rm -rf /Library/Caches/* 2>/dev/null || true
  else
    warn "Skipped system caches."
  fi
fi

if (( logs )); then
  require_sudo
  info "Rotating/compressing logs via newsyslog (where configured)..."
  run sudo newsyslog || true
fi

if (( periodic )); then
  require_sudo
  info "Running periodic daily/weekly/monthly..."
  run sudo periodic daily weekly monthly
fi

if (( brew )); then
  if command -v brew >/dev/null 2>&1; then
    info "Running brew cleanup..."
    run brew cleanup
  else
    warn "Homebrew not found; skipping brew cleanup."
  fi
fi

success "Cleanup complete."

