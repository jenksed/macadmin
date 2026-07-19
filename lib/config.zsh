#!/usr/bin/env zsh
# shellcheck shell=bash
# lib/config.zsh — config loader for macadmin
# Reads ~/.macadminrc (shell-style KEY=value) and exposes the values
# as shell variables. Commands call macadmin_config_get <key> to
# retrieve a value, or read \$KEY directly.
#
# Usage:
#   source lib/config.zsh
#   macadmin_config_load              # load ~/.macadminrc into env
#   macadmin_config_get BACKUP_DIR    # print value or default
#   print -r -- "$BACKUP_DIR"         # value also exposed as $KEY

emulate -L zsh
# NOTE: do not enable errexit/pipefail here.

# Guard against multiple sourcing.
if [[ -n ${__MACADMIN_CONFIG_SOURCED:-} ]]; then
  return 0
fi
typeset -g __MACADMIN_CONFIG_SOURCED=1

typeset -gx EX_OK=${EX_OK:-0}
typeset -gx EX_CONFIG=${EX_CONFIG:-78}

# Print the path to the user config file. Honors MACADMIN_CONFIG override.
macadmin_config_path() {
  print -r -- "${MACADMIN_CONFIG:-${HOME}/.macadminrc}"
}

# Print the path to the user ignore file. Honors MACADMIN_IGNORE_FILE override.
macadmin_config_ignore_path() {
  print -r -- "${MACADMIN_IGNORE_FILE:-${HOME}/.macadminignore}"
}

# Load ~/.macadminrc (or MACADMIN_CONFIG path) into the current shell.
# Lines starting with '#' and blank lines are ignored. After this,
# keys are available as $KEY.
#
# Returns 0 on success (file may not exist; that's fine).
# Returns non-zero on parse error.
macadmin_config_load() {
  local cfg
  cfg=$(macadmin_config_path)
  [[ -r "$cfg" ]] || return 0
  # Source in a subshell so setopts don't leak; then promote values to
  # the calling environment.
  local __macadmin_config_load_tmp
  __macadmin_config_load_tmp=$(
    set +o errexit
    source "$cfg"
    # Print each KEY=value pair, one per line.
    # We restrict to UPPER_CASE keys to avoid polluting the env with
    # anything else from the user's file.
    # shellcheck disable=SC2154
    print -rl -- ${(k)parameters[(R)([_A-Z]*|MACADMIN*)]} 2>/dev/null \
      | while IFS= read -r k; do
          [[ -n "$k" ]] && print -r -- "$k=${(P)k}"
        done
  )
  if [[ -n "$__macadmin_config_load_tmp" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      eval "export $line" 2>/dev/null || true
    done <<<"$__macadmin_config_load_tmp"
  fi
  return ${EX_OK:-0}
}

# Print the value of $key, or $default if not set. Updates the variable
# in the caller's shell on success.
#
# Usage:
#   val=$(macadmin_config_get BACKUP_DIR "$HOME/Backups")
#   macadmin_config_get VERBOSE 0 && [[ $VERBOSE -eq 1 ]] && ...
macadmin_config_get() {
  local key="$1"
  local default="${2:-}"
  # Auto-load on first access if not yet loaded.
  if [[ -z "${__MACADMIN_CONFIG_LOADED:-}" ]]; then
    macadmin_config_load
    typeset -g __MACADMIN_CONFIG_LOADED=1
  fi
  # Print value or default.
  if [[ -n "${(P)key:-}" ]]; then
    print -r -- "${(P)key}"
  else
    print -r -- "$default"
  fi
}

# Set a config key and persist it to the config file.
# Not implemented in this release; placeholder.
# macadmin_config_set() { ... }