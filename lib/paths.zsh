#!/usr/bin/env zsh
# shellcheck shell=bash
# lib/paths.zsh — path accessors for macadmin
# All functions are idempotent. Safe to source multiple times.
#
# Usage:
#   source lib/paths.zsh
#   macadmin_path_user_home

emulate -L zsh
set -o errexit -o nounset -o pipefail

# Guard against multiple sourcing.
if [[ -n ${__MACADMIN_PATHS_SOURCED:-} ]]; then
  return 0
fi
typeset -g __MACADMIN_PATHS_SOURCED=1

# ---------------------------------------------------------------------------
# User paths
# ---------------------------------------------------------------------------

# Resolve a path to its absolute form. Uses zsh's :A modifier.
macadmin_path_abs() {
  print -r -- "${1:A}"
}

# Print the current user's home directory. Reads $HOME.
macadmin_path_user_home() {
  print -r -- "${HOME}"
}

# macOS user Library directory.
macadmin_path_user_library() {
  print -r -- "${HOME}/Library"
}

# User caches (Library/Caches). Default cleanup target.
macadmin_path_user_cache() {
  print -r -- "${HOME}/Library/Caches"
}

# User logs (Library/Logs).
macadmin_path_user_logs() {
  print -r -- "${HOME}/Library/Logs"
}

# User Application Support.
macadmin_path_user_app_support() {
  print -r -- "${HOME}/Library/Application Support"
}

# User preferences (.plist files).
macadmin_path_user_preferences() {
  print -r -- "${HOME}/Library/Preferences"
}

# Standard user directories.
macadmin_path_desktop()   { print -r -- "${HOME}/Desktop"; }
macadmin_path_downloads() { print -r -- "${HOME}/Downloads"; }
macadmin_path_documents() { print -r -- "${HOME}/Documents"; }

# Xcode DerivedData (large; safe to delete).
macadmin_path_xcode_derived_data() {
  print -r -- "${HOME}/Library/Developer/Xcode/DerivedData"
}

# npm/yarn caches (large; safe to delete if not actively building).
macadmin_path_npm_cache()  { print -r -- "${HOME}/.npm/_cacache"; }
macadmin_path_yarn_cache() { print -r -- "${HOME}/Library/Caches/Yarn"; }
macadmin_path_yarn_cache_v6() { print -r -- "${HOME}/.cache/yarn"; }

# Docker Desktop logs.
macadmin_path_docker_logs() {
  print -r -- "${HOME}/Library/Containers/com.docker.docker/Data/log"
}

# ---------------------------------------------------------------------------
# System paths (require sudo for writes)
# ---------------------------------------------------------------------------

macadmin_path_system_cache() { print -r -- "/Library/Caches"; }
macadmin_path_system_logs()  { print -r -- "/var/log"; }

# ---------------------------------------------------------------------------
# macadmin-specific paths (defaults; overridable via config)
# ---------------------------------------------------------------------------

# Where macadmin stores its own state (logs, backups, temp).
macadmin_path_state_dir() {
  local d="${HOME}/.macadmin"
  print -r -- "$d"
}

# Where backups go by default.
macadmin_path_backup_dir() {
  local d="${MACADMIN_BACKUP_DIR:-${HOME}/Backups}"
  print -r -- "$d"
}

# Where human-readable logs go.
macadmin_path_log_dir() {
  local d="${MACADMIN_LOG_DIR:-${HOME}/.macadmin/logs}"
  print -r -- "$d"
}

# Config file location.
macadmin_path_config() {
  local p="${MACADMIN_CONFIG:-${HOME}/.macadminrc}"
  print -r -- "$p"
}

# Ignore file location.
macadmin_path_ignore() {
  local p="${MACADMIN_IGNORE_FILE:-${HOME}/.macadminignore}"
  print -r -- "$p"
}

# Resolve to true if the path exists and is a directory.
macadmin_path_is_dir() {
  [[ -d "$1" ]]
}

# Resolve to true if the path exists and is a file.
macadmin_path_is_file() {
  [[ -f "$1" ]]
}

# Resolve to true if the path exists (any kind).
macadmin_path_exists() {
  [[ -e "$1" ]]
}