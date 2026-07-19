#!/usr/bin/env zsh
# shellcheck shell=bash
# lib/macos.zsh — macOS-specific helpers for macadmin
# Ported from jenksed/mac-scripts/lib/macos.sh with macadmin_ prefix
# and zsh idioms. Each public helper is a thin wrapper around a macOS
# command, providing a stable API for scripts.
#
# Usage:
#   source lib/macos.zsh
#   if macadmin_is_apple_silicon; then ...; fi
#   print -r -- "$(macadmin_arch)"

emulate -L zsh
# NOTE: do not enable errexit/pipefail here.

# Guard against multiple sourcing.
if [[ -n ${__MACADMIN_MACOS_SOURCED:-} ]]; then
  return 0
fi
typeset -g __MACADMIN_MACOS_SOURCED=1

# ---------------------------------------------------------------------------
# Version detection
# ---------------------------------------------------------------------------

# Print the full macOS product version, e.g. "15.6.1".
macadmin_macos_version() {
  command sw_vers -productVersion 2>/dev/null || print -r -- "unknown"
}

# Print the major version, e.g. "15".
macadmin_macos_major() {
  print -r -- "${$(macadmin_macos_version)%%.*}"
}

# Print the minor version, e.g. "6".
macadmin_macos_minor() {
  local v; v=$(macadmin_macos_version)
  print -r -- "${${v#*.}%%.*}"
}

# Return 0 if running macOS >= target, 1 otherwise.
# Usage: macadmin_macos_at_least 13
macadmin_macos_at_least() {
  local target="$1"
  local current
  current=$(macadmin_macos_version)
  # Sort -V picks the smaller version; if target sorts first, target is older.
  [[ "$(printf '%s\n%s\n' "$target" "$current" | command sort -V | head -n1)" == "$target" ]]
}

# ---------------------------------------------------------------------------
# Architecture
# ---------------------------------------------------------------------------

# Print the CPU architecture (arm64 or x86_64).
macadmin_arch() {
  command uname -m 2>/dev/null
}

# Return 0 on Apple Silicon, 1 otherwise.
macadmin_is_apple_silicon() {
  [[ "$(macadmin_arch)" == "arm64" ]]
}

# Return 0 on Intel, 1 otherwise.
macadmin_is_intel() {
  [[ "$(macadmin_arch)" == "x86_64" ]]
}

# ---------------------------------------------------------------------------
# System info
# ---------------------------------------------------------------------------

# Print the computer name (or hostname fallback).
macadmin_hostname() {
  command scutil --get ComputerName 2>/dev/null || command hostname -s
}

# Print the hardware serial number. SENSITIVE.
macadmin_serial() {
  command system_profiler SPHardwareDataType 2>/dev/null \
    | command awk '/Serial Number/ {print $4; exit}'
}

# Print the hardware UUID. SENSITIVE.
macadmin_hardware_uuid() {
  command system_profiler SPHardwareDataType 2>/dev/null \
    | command awk '/Hardware UUID/ {print $3; exit}'
}

# Print the current username.
macadmin_current_user() {
  command whoami
}

# Print the user's full name (from Directory Services).
macadmin_user_fullname() {
  command id -F 2>/dev/null
}

# Print the user's home directory.
macadmin_user_home() {
  eval print -r -- "~$(macadmin_current_user)"
}

# ---------------------------------------------------------------------------
# Cache directory listing
# ---------------------------------------------------------------------------

# Print each existing system cache directory, one per line.
macadmin_list_system_caches() {
  local cache
  for cache in \
    "${HOME}/Library/Caches" \
    "/Library/Caches"
  do
    [[ -d "$cache" ]] && print -r -- "$cache"
  done
}

# ---------------------------------------------------------------------------
# System health
# ---------------------------------------------------------------------------

# Print the percentage of disk space used on the root volume (0-100).
macadmin_disk_usage_pct() {
  command df -h / 2>/dev/null \
    | command awk 'NR==2 {gsub("%",""); print $5; exit}'
}

# Print free memory in bytes (approx; uses vm_stat page count).
macadmin_free_memory_bytes() {
  command vm_stat 2>/dev/null \
    | command awk '/Pages free/ {gsub(/\./, ""); print $3 * 4096; exit}'
}

# Print CPU usage percentage (0-100, sampled over 1 second).
macadmin_cpu_usage_pct() {
  command top -l 1 -n 0 2>/dev/null \
    | command awk '/CPU usage/ {print $3; exit}' \
    | command tr -d '%'
}

# ---------------------------------------------------------------------------
# User notifications
# ---------------------------------------------------------------------------

# Display a macOS notification via osascript.
# Usage: macadmin_notify "Title" "Message"
macadmin_notify() {
  local title="$1"
  local message="$2"
  command osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Gatekeeper
# ---------------------------------------------------------------------------

# Print the current Gatekeeper status.
macadmin_gatekeeper_status() {
  command spctl --status 2>&1
}

# Disable Gatekeeper. REQUIRES --yes (caller's responsibility).
macadmin_gatekeeper_disable() {
  command sudo spctl --master-disable
}

# Enable Gatekeeper. REQUIRES --yes (caller's responsibility).
macadmin_gatekeeper_enable() {
  command sudo spctl --master-enable
}

# ---------------------------------------------------------------------------
# Spotlight
# ---------------------------------------------------------------------------

# Reindex Spotlight for $1 (default /).
# REQUIRES --yes (caller's responsibility).
macadmin_spotlight_reindex() {
  local target="${1:-/}"
  command sudo mdutil -E "$target"
}

# Disable Spotlight indexing for $1 (default /).
# REQUIRES --yes (caller's responsibility).
macadmin_spotlight_disable() {
  local target="${1:-/}"
  command sudo mdutil -i off "$target"
}

# Enable Spotlight indexing for $1 (default /).
# REQUIRES --yes (caller's responsibility).
macadmin_spotlight_enable() {
  local target="${1:-/}"
  command sudo mdutil -i on "$target"
}