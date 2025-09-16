#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

ROOT=${0:a:h}/..
cd "$ROOT" || exit 1

rc=0
chmod +x tests/mocks/* 2>/dev/null || true
for f in tests/test_*.zsh; do
  print -r -- "# Running $f"
  out=$(zsh "$f" 2>&1); st=$?
  if (( st != 0 )); then
    print -r -- "FAILED: $f"
    print -r -- "$out"
    rc=1
  else
    print -r -- "$out"
  fi
done

if (( rc == 0 )); then
  print -r -- "All tests passed."
else
  print -r -- "Some tests failed."
fi
exit $rc
