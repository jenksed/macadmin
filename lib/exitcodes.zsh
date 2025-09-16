#!/usr/bin/env zsh
# shellcheck shell=bash
emulate -L zsh
setopt errexit nounset pipefail

# Guard to allow safe re-sourcing
if [[ -n ${__MACADMIN_EXITCODES_SOURCED:-} ]]; then
  return 0
fi
typeset -g __MACADMIN_EXITCODES_SOURCED=1

# Standard sysexits(3)-style exit codes
# Exported and readonly.
typeset -gxr EX_OK=0
typeset -gxr EX_USAGE=64
typeset -gxr EX_DATAERR=65
typeset -gxr EX_NOINPUT=66
typeset -gxr EX_NOUSER=67
typeset -gxr EX_NOHOST=68
typeset -gxr EX_UNAVAILABLE=69
typeset -gxr EX_SOFTWARE=70
typeset -gxr EX_OSERR=71
typeset -gxr EX_OSFILE=72
typeset -gxr EX_CANTCREAT=73
typeset -gxr EX_IOERR=74
typeset -gxr EX_TEMPFAIL=75
typeset -gxr EX_PROTOCOL=76
typeset -gxr EX_NOPERM=77
typeset -gxr EX_CONFIG=78

