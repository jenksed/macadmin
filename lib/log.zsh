#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
emulate -L zsh
setopt errexit nounset pipefail

# Guard to allow safe re-sourcing
if [[ -n ${__MACADMIN_LOG_SOURCED:-} ]]; then
  return 0
fi
typeset -g __MACADMIN_LOG_SOURCED=1

# Optional exit codes (do not hard-require if not present)
{
  local _this=${(%):-%N}
  local _dir=${_this:A:h}
  if [[ -r "$_dir/exitcodes.zsh" ]]; then
    source "$_dir/exitcodes.zsh" 2>/dev/null || true
  fi
}
# Provide fallback if not defined (avoid clobbering readonly vars)
if [[ -z ${EX_NOPERM+x} ]]; then
  typeset -g EX_NOPERM=77
fi

# Defaults for env toggles if not already set
typeset -g MACADMIN_JSON=${MACADMIN_JSON:-0}
typeset -g MACADMIN_VERBOSE=${MACADMIN_VERBOSE:-0}
typeset -g MACADMIN_QUIET=${MACADMIN_QUIET:-0}

_macadmin_ts() {
  # ISO-8601 UTC timestamp
  date -u +%Y-%m-%dT%H:%M:%SZ
}

_macadmin_cmd() {
  local name
  name=${MACADMIN_CMD:-${MACADMIN_COMMAND:-${ZSH_NAME:-${0:t}}}}
  print -r -- "$name"
}

_json_escape() {
  # Minimal JSON string escaper
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  print -r -- "$s"
}

_emit_json() {
  # _emit_json <level> <message> [data-json]
  local level="$1" msg="$2" datajson="${3:-null}"
  local ts cmd escmsg
  ts=$(_macadmin_ts)
  cmd=$(_macadmin_cmd)
  escmsg=$(_json_escape "$msg")
  print -r -- "{"\
"\"ts\":\"$ts\",\"level\":\"$level\",\"cmd\":\"$cmd\",\"message\":\"$escmsg\",\"data\":$datajson}"
}

log_info() {
  # log_info <message...>
  (( MACADMIN_QUIET )) && return 0
  local msg="$*"
  if (( MACADMIN_JSON )); then
    _emit_json info "$msg"
  else
    print -r -- "[INFO] $msg"
  fi
}

log_warn() {
  # log_warn <message...>
  (( MACADMIN_QUIET )) && return 0
  local msg="$*"
  if (( MACADMIN_JSON )); then
    _emit_json warn "$msg"
  else
    print -r -- "[WARN] $msg" >&2
  fi
}

log_error() {
  # log_error <message...>
  local msg="$*"
  if (( MACADMIN_JSON )); then
    _emit_json error "$msg"
  else
    print -r -- "[ERROR] $msg" >&2
  fi
}

log_debug() {
  # log_debug <message...> (prints only with verbose and not quiet)
  (( MACADMIN_QUIET )) && return 0
  (( MACADMIN_VERBOSE )) || return 0
  local msg="$*"
  if (( MACADMIN_JSON )); then
    _emit_json debug "$msg"
  else
    print -r -- "[DEBUG] $msg"
  fi
}

log_json() {
  # log_json <event> <payload-json>
  local event="$1"; shift || true
  local payload="${1:-null}"
  if (( MACADMIN_JSON )); then
    _emit_json event "$event" "$payload"
  else
    # Human-readable fallback
    print -r -- "event: $event $payload"
  fi
}

confirm_or_exit() {
  # confirm_or_exit [prompt]
  local prompt="${1:-Proceed?}"
  if [[ ${MACADMIN_YES:-0} -eq 1 ]]; then
    log_debug "Auto-confirmed (MACADMIN_YES=1)"
    return 0
  fi
  printf "%s [y/N]: " "$prompt" >&2
  local reply=""
  read -r reply || reply=""
  if [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]; then
    return 0
  fi
  log_error "Aborted by user"
  return $EX_NOPERM
}
