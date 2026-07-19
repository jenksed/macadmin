#!/usr/bin/env zsh
# shellcheck shell=bash
# lib/safety.zsh — safety primitives for macadmin
# Centralizes allowlist checking, confirm prompts, and the
# MACADMIN_PROTECT gate. Code that mutates user data should ALWAYS
# invoke these helpers before performing destructive actions.
#
# Usage:
#   source lib/safety.zsh
#   macadmin_safety_allowlist_check "$path" || exit $EX_NOPERM
#   macadmin_safety_within "$path" "$root" || die "out of bounds"
#   macadmin_safety_protect_gate "delete /tmp/foo"

emulate -L zsh
# NOTE: deliberately do NOT enable errexit/pipefail/nounset at library
# level. Safety helpers return non-zero to signal "bad" and callers must
# check. errexit would propagate those returns and exit the caller.

# Guard against multiple sourcing.
if [[ -n ${__MACADMIN_SAFETY_SOURCED:-} ]]; then
  return 0
fi
typeset -g __MACADMIN_SAFETY_SOURCED=1

# Declare sysexits codes locally without sourcing exitcodes.zsh, which
# itself sets errexit/pipefail/nounset. Each constant is defined only
# if not already present, so callers that loaded exitcodes.zsh first
# keep their values. Use 'typeset +x' first to make the variable
# writable (in case it was previously declared read-only by
# exitcodes.zsh).
[[ -z ${EX_OK+x} ]] && { typeset -gx EX_OK=0; } || true
[[ -z ${EX_USAGE+x} ]] && { typeset -gx EX_USAGE=64; } || true
[[ -z ${EX_DATAERR+x} ]] && { typeset -gx EX_DATAERR=65; } || true
[[ -z ${EX_NOINPUT+x} ]] && { typeset -gx EX_NOINPUT=66; } || true
[[ -z ${EX_NOPERM+x} ]] && { typeset -gx EX_NOPERM=77; } || true
[[ -z ${EX_CONFIG+x} ]] && { typeset -gx EX_CONFIG=78; } || true

# ---------------------------------------------------------------------------
# Path validation
# ---------------------------------------------------------------------------

# macOS system paths that macadmin should never delete from.
# Use literal prefix matches; do NOT use globs (zsh would expand them
# at typeset time, producing hundreds of entries).
#
# Notes:
#   - /private is NOT listed: /private/var/folders/... is per-user temp,
#     which is user-writable and macadmin may legitimately delete from.
#   - /var is NOT listed: same reason (/var/folders is per-user temp).
#     /var/log and /var/audit must be guarded separately by callers.
#   - /tmp is NOT listed: BSD-style shared temp; user-writable.
#
# This list is the FIRST line of defense. macadmin's safety model also
# requires explicit allowlists for mutating commands.
typeset -ga MACADMIN_SYSTEM_PATHS=(
  /
  /System
  /usr
  /bin
  /sbin
  /etc
  /private/etc
  /private/var/log
  /private/var/audit
)

# Return 0 if $1 is a "safe" path (not a system path), 1 otherwise.
# Accepts both bare paths and absolute paths.
macadmin_safety_path_is_safe() {
  local target="$1"
  # Reject empty paths.
  [[ -z "$target" ]] && return 1
  # Reject root.
  [[ "$target" == "/" ]] && return 1
  # Resolve to absolute.
  local abs="${target:A}"
  # Walk the system path prefixes.
  local sys
  for sys in "${MACADMIN_SYSTEM_PATHS[@]}"; do
    # Match the prefix: /etc matches /etc/passwd.
    [[ "$abs" == "$sys" ]] && return 1
    [[ "$abs" == "$sys"/* ]] && return 1
  done
  return 0
}

# Return 0 if $path is within one of the allowlist roots, 1 otherwise.
# Usage: macadmin_safety_within "$path" "${ALLOW_ROOTS[@]}"
macadmin_safety_within() {
  local target="$1"
  shift
  local abs="${target:A}"
  local root
  for root in "$@"; do
    local r="${root:A}"
    [[ "$abs" == "$r" ]] && return 0
    [[ "$abs" == ${r%/}/* ]] && return 0
  done
  return 1
}

# Strict allowlist check: prints a warning if $1 is outside the given roots.
# Returns 0 if allowed, 1 if not. Logs the reason to stderr.
# Usage: macadmin_safety_allowlist_check "$path" "${ALLOW_ROOTS[@]}" || exit $EX_NOPERM
macadmin_safety_allowlist_check() {
  local target="$1"
  shift
  if macadmin_safety_path_is_safe "$target"; then
    return 0
  fi
  print -r -- "[ERROR] refusing to operate on system path: $target" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Confirmation prompts
# ---------------------------------------------------------------------------

# Print a warning and wait for y/N. Returns 0 on yes, 1 on no.
# Honors MACADMIN_YES (skips prompt, returns 0 if set to 1).
macadmin_safety_confirm() {
  local prompt="${1:-Proceed?}"
  if (( ${MACADMIN_YES:-0} )); then
    print -r -- "[INFO] auto-confirmed (MACADMIN_YES=1): $prompt" >&2
    return 0
  fi
  local reply=""
  printf "%s [y/N]: " "$prompt" >&2
  read -r reply || reply=""
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Confirm and exit with EX_NOPERM if user declines.
# Usage: macadmin_safety_confirm_or_exit "delete ~/.cache/foo"
macadmin_safety_confirm_or_exit() {
  local prompt="$1"
  if macadmin_safety_confirm "$prompt"; then
    return 0
  fi
  print -r -- "[ERROR] aborted by user" >&2
  return ${EX_NOPERM:-77}
}

# ---------------------------------------------------------------------------
# Protect gate
# ---------------------------------------------------------------------------

# The MACADMIN_PROTECT gate: refuse to proceed if PROTECT is set and
# YES is not. Use this at the top of every mutating command's action
# body. Prints a clear error and returns EX_NOPERM.
#
# Usage:
#   macadmin_safety_protect_gate "delete cache directory" || return $?
macadmin_safety_protect_gate() {
  local action="${1:-mutate}"
  if (( ${MACADMIN_PROTECT:-0} )) && (( ! ${MACADMIN_YES:-0} )); then
    print -r -- "[ERROR] refusing to ${action} under --protect without --yes" >&2
    return ${EX_NOPERM:-77}
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Ignore-file helpers
# ---------------------------------------------------------------------------

# Load patterns from $HOME/.macadminignore into _MACADMIN_IGNORE_PATTERNS.
# Empty lines and comments (#) are skipped.
macadmin_safety_load_ignore() {
  typeset -ga _MACADMIN_IGNORE_PATTERNS=()
  local file="${MACADMIN_IGNORE_FILE:-${HOME}/.macadminignore}"
  [[ -r "$file" ]] || return 0
  local line
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    _MACADMIN_IGNORE_PATTERNS+=("$line")
  done < "$file"
}

# Return 0 if $path matches a loaded ignore pattern, 1 otherwise.
# Patterns starting with '/' (or after expansion, starting with the
# absolute HOME) match absolute paths (prefix match). All other
# patterns match against the basename of the path. A leading '~' is
# expanded to $HOME.
macadmin_safety_ignored() {
  local target="$1"
  local pat
  local pattmp
  [[ ${#_MACADMIN_IGNORE_PATTERNS[@]} -eq 0 ]] && return 1
  for pat in "${_MACADMIN_IGNORE_PATTERNS[@]}"; do
    # Expand leading ~ to $HOME. The '~' must be escaped in the pattern
    # so zsh does not treat it as a glob-special character.
    pattmp="$pat"
    case "$pattmp" in
      "~"*) pattmp="${pattmp/#\~/$HOME}" ;;
    esac
    # Absolute patterns match against the full path with prefix semantics.
    # Non-absolute patterns match against the basename.
    if [[ "$pattmp" == /* ]]; then
      # Prefix match: target is under pattmp or equals it.
      if [[ "$target" == "$pattmp" || "$target" == "$pattmp"/* ]]; then
        return 0
      fi
    else
      # Basename match: target's basename equals pattmp (with glob).
      [[ "${target:t}" == $~pattmp ]] && return 0
    fi
  done
  return 1
}