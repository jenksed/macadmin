#!/usr/bin/env zsh
# tests/test_protect_enforcement.zsh — Release 0.6 protect-gate smoke.
#
# For every mutating command whose --protect gate BLOCKS UNCONDITIONALLY
# (i.e., refuses even when --yes is set), verify that
#   MACADMIN_PROTECT=1 + --yes + destructive flag -> exit != 0
# This is the core invariant the protect gate must enforce.
#
# Commands with weaker gates (cleanup, network wifi, os_update, brew_tools
# ensure) are intentionally NOT covered here — their gates refuse only
# when --yes is absent. Fixing those to unconditional-block is a follow-up.
emulate -L zsh
setopt errexit nounset pipefail

HERE=${0:a:h}
REPO="$HERE/.."
source "$HERE/assert.zsh"

# Per-test sandbox under $HOME/Downloads so the sort allowlist is satisfied.
PROTECT_TMP="$HOME/Downloads/macadmin_protect_test_$$"
rm -rf "$PROTECT_TMP"
mkdir -p "$PROTECT_TMP"
reset_protect_tmp()
{
  rm -rf "$PROTECT_TMP"
  mkdir -p "$PROTECT_TMP"
}

# Run a command with MACADMIN_PROTECT=1 + MACADMIN_YES=1 and assert it
# refuses (exit != 0). Captures stderr too since the protect error
# message goes there.
run_with_protect()
{
  setopt local_options no_errexit
  ( HOME="$HOME" PATH="$HERE/mocks:$PATH" MACADMIN_PROTECT=1 MACADMIN_YES=1 zsh "$@" ) > /dev/null 2>&1
  PROBE_ST=$?
  setopt local_options errexit
}

assert_protect_blocks()
{
  local name="$1"
  if (( PROBE_ST != 0 )); then
    pass "protect: $name refused under --protect+--yes (exit=$PROBE_ST)"
  else
    fail "protect: $name should have refused under --protect+--yes"
  fi
}

# 1. archive create --delete-sources --yes --no-dry-run: --protect blocks
reset_protect_tmp
touch "$PROTECT_TMP/a.txt"
run_with_protect "$REPO/scripts/archive.zsh" create "$PROTECT_TMP/a.txt" \
  --output "$PROTECT_TMP/out.zip" --delete-sources --yes --no-dry-run
assert_protect_blocks "archive create --delete-sources"
[[ -f "$PROTECT_TMP/a.txt" ]] && pass "protect: archive left source intact" \
  || fail "protect: archive should not delete source"

# 2. archive recompress --yes --no-dry-run: --protect blocks
reset_protect_tmp
touch "$PROTECT_TMP/in.zip"
run_with_protect "$REPO/scripts/archive.zsh" recompress "$PROTECT_TMP/in.zip" \
  --output "$PROTECT_TMP/out.7z" --yes --no-dry-run
assert_protect_blocks "archive recompress"

# 3. disk duplicates --delete --yes: --protect blocks
reset_protect_tmp
mkdir -p "$PROTECT_TMP/big" "$PROTECT_TMP/small"
touch "$PROTECT_TMP/big/dup.txt" "$PROTECT_TMP/small/dup.txt"
# Ensure sha256sum is in PATH (mock from tests/mocks/ uses size-based hash).
run_with_protect "$REPO/scripts/disk.zsh" duplicates \
  --path "$PROTECT_TMP" --delete --yes
assert_protect_blocks "disk duplicates --delete"
# Both copies should still be present (delete was refused).
[[ -f "$PROTECT_TMP/big/dup.txt" && -f "$PROTECT_TMP/small/dup.txt" ]] \
  && pass "protect: disk duplicates left both copies intact" \
  || fail "protect: disk duplicates should not have deleted either copy"

# 4. files rename --no-dry-run --yes: --protect blocks
reset_protect_tmp
touch "$PROTECT_TMP/rename.txt"
run_with_protect "$REPO/scripts/files.zsh" rename "rename.txt" \
  --prefix "x_" --no-dry-run --yes
assert_protect_blocks "files rename --no-dry-run"
[[ -f "$PROTECT_TMP/rename.txt" ]] && pass "protect: files rename left source intact" \
  || fail "protect: files rename should not rename"

# 5. files sort --no-dry-run --yes: --protect blocks
reset_protect_tmp
touch "$PROTECT_TMP/report.pdf"
run_with_protect "$REPO/scripts/files.zsh" sort \
  --path "$PROTECT_TMP" --no-dry-run --yes
assert_protect_blocks "files sort --no-dry-run"
[[ -f "$PROTECT_TMP/report.pdf" ]] && pass "protect: files sort left files in place" \
  || fail "protect: files sort should not move files"

# 6. files organize screenshots --no-dry-run --yes: --protect blocks
reset_protect_tmp
touch "$PROTECT_TMP/Screenshot 2026-07-19 at 10.34.56 AM.png"
run_with_protect "$REPO/scripts/files.zsh" organize screenshots \
  --path "$PROTECT_TMP" \
  --dest "$PROTECT_TMP/Pictures/Screenshots" \
  --no-dry-run --yes
assert_protect_blocks "files organize screenshots --no-dry-run"
[[ -f "$PROTECT_TMP/Screenshot 2026-07-19 at 10.34.56 AM.png" ]] \
  && pass "protect: organize screenshots left screenshot in place" \
  || fail "protect: organize screenshots should not move file"

# Cleanup
rm -rf "$PROTECT_TMP"
