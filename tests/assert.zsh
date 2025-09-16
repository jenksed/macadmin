#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

pass() { print -r -- "ok - $*"; }
fail() { print -r -- "not ok - $*"; return 1 }

# Run a command, capturing stdout+stderr and exit code
# Usage: run_cmd <var_prefix> -- <cmd...>
run_cmd() {
  local __prefix="$1"; shift
  [[ "$1" == "--" ]] && shift
  local __out __status
  __out=$("$@" 2>&1); __status=$?
  eval ${__prefix}_OUT="${__out:q}"
  eval ${__prefix}_STATUS=${__status}
}

assert_exit0() {
  local st=$1 name=$2
  if (( st == 0 )); then pass "$name"; else print -r -- "$name: exit=$st"; fail "$name"; fi
}

assert_contains() {
  local haystack=$1 needle=$2 name=$3
  if print -r -- "$haystack" | grep -Fq -- "$needle"; then pass "$name"; else print -r -- "missing: $needle"; fail "$name"; fi
}
