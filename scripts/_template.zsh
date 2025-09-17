#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
emulate -L zsh
setopt errexit nounset pipefail

# Template command script for macadmin
# Usage block includes one-line summary for dispatcher discovery.
usage() {
  cat <<'EOF'
_template.zsh - concise one-line description here

Usage:
  _template.zsh [options]

Flags:
  -h, --help   Show this help

Notes:
  - Honors global env toggles set by dispatcher:
    MACADMIN_DRY_RUN, MACADMIN_YES, MACADMIN_VERBOSE, MACADMIN_JSON,
    MACADMIN_QUIET, MACADMIN_PROTECT
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

# Example top-level behavior
if (( ${MACADMIN_JSON:-0} )); then
  # Use shared JSON emitter for consistency
  macadmin_json_obj ok=true; printf '\n'
else
  printf 'Template executed.\n'
fi
