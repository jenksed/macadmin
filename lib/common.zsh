#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

# Colors for human-readable mode only
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

# Wire in logging + exit codes (safe to re-source)
{ local _dir=${(%):-%N}; _dir=${_dir:A:h}; [[ -r "$_dir/log.zsh" ]] && source "$_dir/log.zsh"; } || true
{ local _dir=${(%):-%N}; _dir=${_dir:A:h}; [[ -r "$_dir/exitcodes.zsh" ]] && source "$_dir/exitcodes.zsh"; } || true

# Backward-compatible logging shims calling new log_* helpers
info()    { (( ${MACADMIN_JSON:-0} )) && { log_info "$@"; return; }; print -r -- "${C[blue]}[INFO]${C[reset]} $*"; }
warn()    { (( ${MACADMIN_JSON:-0} )) && { log_warn "$@"; return; }; print -r -- "${C[yellow]}[WARN]${C[reset]} $*" >&2; }
error()   { (( ${MACADMIN_JSON:-0} )) && { log_error "$@"; return; }; print -r -- "${C[red]}[ERROR]${C[reset]} $*" >&2; }
success() { (( ${MACADMIN_JSON:-0} )) && { log_info "$@"; return; }; print -r -- "${C[green]}[OK]${C[reset]} $*"; }

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
  # Be tolerant of mocks: accept any uname output containing "Darwin".
  local us
  us=$(uname -s 2>/dev/null || uname 2>/dev/null || echo "")
  if [[ "$us" != *Darwin* ]]; then
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
