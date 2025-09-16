#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

# Colors
typeset -gA C
C=(
  reset $'\e[0m'
  bold  $'\e[1m'
  dim   $'\e[2m'
  red   $'\e[31m'
  green $'\e[32m'
  yellow $'\e[33m'
  blue  $'\e[34m'
)

# Logging
info()    { print -r -- "${C[blue]}[INFO]${C[reset]} $*"; }
warn()    { print -r -- "${C[yellow]}[WARN]${C[reset]} $*" >&2; }
error()   { print -r -- "${C[red]}[ERROR]${C[reset]} $*" >&2; }
success() { print -r -- "${C[green]}[OK]${C[reset]} $*"; }

# Dry-run aware runner
run() {
  if [[ -n "${DRY_RUN:-}" ]]; then
    print -r -- "${C[dim]}$ ${(q@)@}${C[reset]}"
  else
    command "$@"
  fi
}

# Require macOS
require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    error "This script is intended for macOS (Darwin)."
    return 1
  fi
}

# Command availability
require_cmd() {
  local cmd="$1"
  if ! command -v -- "$cmd" >/dev/null 2>&1; then
    error "Missing required command: $cmd"
    return 1
  fi
}

# Prompt for sudo once
require_sudo() {
  if [[ -n "${DRY_RUN:-}" ]]; then
    warn "DRY_RUN set: skipping sudo elevation"
    return 0
  fi
  if ! sudo -n true 2>/dev/null; then
    info "Requesting sudo rights..."
    sudo -v
  fi
}

confirm() {
  local prompt=${1:-"Proceed?"}
  local reply
  printf "%s [y/N]: " "$prompt" >&2
  read -r reply || return 1
  [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]
}

die() { error "$*"; return 1 }

