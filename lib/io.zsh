#!/usr/bin/env zsh
# shellcheck shell=bash
# lib/io.zsh — file I/O helpers for macadmin
# Centralizes atomic writes, backups, temp directory management,
# and safe removal. Built on lib/safety.zsh for path validation.
#
# Usage:
#   source lib/io.zsh
#   macadmin_io_backup_file ~/.zshrc
#   macadmin_io_safe_rm /tmp/old-file || echo "refused"

emulate -L zsh
# NOTE: do not enable errexit/pipefail here (see lib/safety.zsh).

# Guard against multiple sourcing.
if [[ -n ${__MACADMIN_IO_SOURCED:-} ]]; then
  return 0
fi
typeset -g __MACADMIN_IO_SOURCED=1

# Source dependencies without re-enabling their errexit.
# shellcheck source=lib/safety.zsh
{
  set +o errexit
  source "${0:A:h}/safety.zsh" 2>/dev/null || true
}

typeset -gx EX_OK=${EX_OK:-0}
typeset -gx EX_NOINPUT=${EX_NOINPUT:-66}
typeset -gx EX_CANTCREAT=${EX_CANTCREAT:-73}
typeset -gx EX_NOPERM=${EX_NOPERM:-77}

# ---------------------------------------------------------------------------
# Safe remove
# ---------------------------------------------------------------------------

# Refuse to remove a path. Returns:
#   0 if removed
#   1 if path did not exist (no-op)
#   2 if path is in a system directory
#   3 if path is outside an allowlist (when ALLOW_ROOTS is set as env)
#
# Usage:
#   macadmin_io_safe_rm /tmp/foo
#   MACADMIN_IO_ALLOW_ROOTS="/Users/me /tmp" macadmin_io_safe_rm /tmp/foo
macadmin_io_safe_rm() {
  local target="$1"
  [[ -e "$target" ]] || return 1
  if ! macadmin_safety_path_is_safe "$target"; then
    print -r -- "[ERROR] refusing to remove system path: $target" >&2
    return 2
  fi
  # Optional per-call allowlist.
  if [[ -n "${MACADMIN_IO_ALLOW_ROOTS:-}" ]]; then
    # Split on whitespace.
    local -a roots
    roots=(${(z)MACADMIN_IO_ALLOW_ROOTS})
    if ! macadmin_safety_within "$target" "${roots[@]}"; then
      print -r -- "[ERROR] refusing to remove outside allowlist: $target" >&2
      return 3
    fi
  fi
  # If dry-run, print what would happen.
  if (( ${MACADMIN_DRY_RUN:-0} )); then
    print -r -- "[INFO] DRY_RUN: would remove $target" >&2
    return 0
  fi
  rm -rf -- "$target"
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

# Copy $1 to a timestamped backup under $2 (default: macadmin_path_backup_dir).
# Returns 0 on success, 1 if source missing, 2 on copy error.
macadmin_io_backup_file() {
  local src="$1"
  local dest_dir="${2:-${MACADMIN_BACKUP_DIR:-${HOME}/Backups}}"
  [[ -e "$src" ]] || return 1
  mkdir -p -- "$dest_dir" 2>/dev/null || return 2
  local ts base
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)
  base=${src:t}
  local dest="${dest_dir}/${base}.${ts}"
  cp -p -- "$src" "$dest" 2>/dev/null || return 2
  print -r -- "$dest"
}

# ---------------------------------------------------------------------------
# Temp directory management
# ---------------------------------------------------------------------------

# Per-script temp directory. Set on first call; cleaned on EXIT.
typeset -g MACADMIN_TEMP_DIR=""

# Print the temp directory path as a settable form.
# Idempotent: subsequent calls return the same path.
# Use as: eval "$(macadmin_io_temp_dir)"
#   or:   MACADMIN_TEMP_DIR=$(macadmin_io_temp_dir)
#         # When used with $(), MACADMIN_TEMP_DIR is set in the parent
#         # because we emit an assignment form.
macadmin_io_temp_dir() {
  # If we already have a temp dir, emit it as an assignment.
  if [[ -n "$MACADMIN_TEMP_DIR" && -d "$MACADMIN_TEMP_DIR" ]]; then
    print -r -- "MACADMIN_TEMP_DIR='$MACADMIN_TEMP_DIR'"
    return 0
  fi
  # Create a new one.
  local tmp
  tmp=$(mktemp -d -t macadmin.XXXXXX 2>/dev/null) || {
    print -r -- "[ERROR] failed to create temp dir" >&2
    return 1
  }
  # Auto-cleanup on EXIT.
  trap '[[ -n "$MACADMIN_TEMP_DIR" && -d "$MACADMIN_TEMP_DIR" ]] && rm -rf -- "$MACADMIN_TEMP_DIR"' EXIT
  # Emit as an assignment so callers can capture with eval or $().
  print -r -- "MACADMIN_TEMP_DIR='$tmp'"
}

# Explicit cleanup. Idempotent.
macadmin_io_temp_cleanup() {
  [[ -n "$MACADMIN_TEMP_DIR" && -d "$MACADMIN_TEMP_DIR" ]] && rm -rf -- "$MACADMIN_TEMP_DIR"
  MACADMIN_TEMP_DIR=""
}

# ---------------------------------------------------------------------------
# Atomic write
# ---------------------------------------------------------------------------

# Write $content to $path atomically (via temp + rename).
# Returns 0 on success, non-zero on failure.
#
# Usage:
#   macadmin_io_atomic_write ~/.macadminrc "BACKUP_DIR=\$HOME/Backups\n"
macadmin_io_atomic_write() {
  # Note: do NOT name the parameter 'path' — zsh reserves that name for
  # the $PATH array, and `local path` would shadow it and break command
  # lookup for the rest of the function (and the caller).
  local target="$1"
  local content="$2"
  local dir="${target:h}"
  [[ -d "$dir" ]] || mkdir -p -- "$dir" || return ${EX_CANTCREAT:-73}
  local tmpfile
  tmpfile=$(mktemp -t macadmin.XXXXXX) || return ${EX_CANTCREAT:-73}
  if ! print -r -- "$content" > "$tmpfile"; then
    rm -f -- "$tmpfile"
    return ${EX_IOERR:-74}
  fi
  if ! mv -f -- "$tmpfile" "$target"; then
    rm -f -- "$tmpfile"
    return ${EX_IOERR:-74}
  fi
  return ${EX_OK:-0}
}

# ---------------------------------------------------------------------------
# Read helpers
# ---------------------------------------------------------------------------

# Print each non-empty, non-comment line of $1.
# Usage: macadmin_io_read_lines <path>
macadmin_io_read_lines() {
  local path="$1"
  [[ -r "$path" ]] || return 1
  local line
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    print -r -- "$line"
  done < "$path"
}