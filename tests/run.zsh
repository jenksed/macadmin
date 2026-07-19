#!/usr/bin/env zsh
# tests/run.zsh — test runner.
#
# Usage:
#   tests/run.zsh                # run all tests/test_*.zsh
#   tests/run.zsh protect         # run only tests/test_protect*.zsh
#                                  # (used by `make protect-check`)
#   tests/run.zsh <glob>          # run tests matching glob
emulate -L zsh
setopt errexit nounset pipefail

ROOT=${0:a:h}/..
cd "$ROOT" || exit 1

# Pick which test files to run based on the first argument.
case "${1:-all}" in
  all|"")    set -- tests/test_*.zsh ;;
  protect)   set -- tests/test_protect*.zsh ;;
  *)
    # Treat the argument as a glob pattern (e.g. tests/test_disk.zsh).
    set -- "$@"
    ;;
esac

rc=0
chmod +x tests/mocks/* 2>/dev/null || true
for f in "$@"; do
  [[ -e "$f" ]] || continue
  print -r -- "# Running $f"
  out=$(zsh "$f" 2>&1)
  st=$?
  if ((st != 0)); then
    print -r -- "FAILED: $f"
    print -r -- "$out"
    rc=1
  else
    print -r -- "$out"
  fi
done

if ((rc == 0)); then
  print -r -- "All tests passed."
else
  print -r -- "Some tests failed."
fi
exit $rc

