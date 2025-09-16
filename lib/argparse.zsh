#!/usr/bin/env zsh
# shellcheck shell=bash
emulate -L zsh
setopt errexit nounset pipefail

# Guard to allow safe re-sourcing
if [[ -n ${__MACADMIN_ARGPARSE_SOURCED:-} ]]; then
  return 0
fi
typeset -g __MACADMIN_ARGPARSE_SOURCED=1

# Defaults
typeset -g MACADMIN_JSON=${MACADMIN_JSON:-0}
typeset -g MACADMIN_VERBOSE=${MACADMIN_VERBOSE:-0}
typeset -g MACADMIN_DRY_RUN=${MACADMIN_DRY_RUN:-0}
typeset -g MACADMIN_YES=${MACADMIN_YES:-0}
typeset -g MACADMIN_PROTECT=${MACADMIN_PROTECT:-0}
typeset -g MACADMIN_QUIET=${MACADMIN_QUIET:-0}

# Resulting non-global args after parsing
typeset -ga MACADMIN_ARGS

macadmin_globals_help() {
  cat <<'EOF'
Global flags:
  --dry-run    Print actions without executing (also sets DRY_RUN)
  --yes        Assume yes for prompts; allow destructive ops
  --verbose    Increase verbosity (mutually exclusive with --quiet)
  --json       JSON output (commands should honor when supported)
  --quiet      Reduce non-essential output (mutually exclusive with --verbose)
  --protect    Extra safety guard for destructive commands
  --           Stop parsing global flags; pass the rest to command
EOF
}

macadmin_parse_globals() {
  # Usage: macadmin_parse_globals "$@"
  # Side effects: sets and exports MACADMIN_* vars; fills MACADMIN_ARGS with remaining args.
  MACADMIN_ARGS=()
  local -a in; in=($@)
  local i=1
  while (( i <= ${#in} )); do
    case "${in[i]}" in
      --dry-run)  MACADMIN_DRY_RUN=1 ;;
      --yes)      MACADMIN_YES=1 ;;
      --verbose)  MACADMIN_VERBOSE=1 ;;
      --json)     MACADMIN_JSON=1 ;;
      --quiet)    MACADMIN_QUIET=1 ;;
      --protect)  MACADMIN_PROTECT=1 ;;
      --)         (( i++ )); while (( i <= ${#in} )); do MACADMIN_ARGS+="${in[i]}"; (( i++ )); done; break ;;
      -*)         MACADMIN_ARGS+="${in[i]}" ;;
      *)          MACADMIN_ARGS+="${in[i]}" ;;
    esac
    (( i++ ))
  done

  # Enforce mutual exclusion: quiet vs verbose -> quiet wins
  if (( MACADMIN_QUIET )); then MACADMIN_VERBOSE=0; fi

  # Export for subcommands and helpers
  export MACADMIN_DRY_RUN MACADMIN_YES MACADMIN_VERBOSE MACADMIN_JSON MACADMIN_QUIET MACADMIN_PROTECT
  # Back-compat for helpers expecting DRY_RUN
  if (( MACADMIN_DRY_RUN )); then export DRY_RUN=1; fi

  return 0
}

