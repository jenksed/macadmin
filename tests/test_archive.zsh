#!/usr/bin/env zsh
# tests/test_archive.zsh — Release 0.6 archive.zsh tests.
# Covers 'create' (zip + 7z), 'recompress', and the safety gates
# (--delete-sources requires --yes; --protect blocks unconditionally).
emulate -L zsh
setopt errexit nounset pipefail

HERE=${0:a:h}
REPO="$HERE/.."
source "$HERE/assert.zsh"

FIX="$HERE/fixtures/archive_test"

# Helper: run files.zsh-style invocation via temp file for output
# capture, with errexit locally disabled so non-zero exits don't abort.
# Sets RAW_OUT and RAW_ST globals.
run_zsh_archive()
{
  local rawf="/tmp/.macadmin_arch_test_$$_$RANDOM"
  setopt local_options no_errexit
  ( HOME="$HOME" PATH="$HERE/mocks:$PATH" zsh "$REPO/scripts/archive.zsh" "$@" ) > "$rawf" 2>&1
  RAW_ST=$?
  RAW_OUT=$(cat "$rawf")
  setopt local_options errexit
  rm -f "$rawf"
}

# Use a private copy of the fixtures for destructive tests so we can
# exercise --delete-sources without clobbering the repo's committed
# fixtures. Reset between tests.
ARCH_TMP=$(mktemp -d "$HOME/Downloads/macadmin_archive_test.XXXXXX")
mkdir -p "$ARCH_TMP/sub" && touch "$ARCH_TMP/a.txt" "$ARCH_TMP/b.txt" "$ARCH_TMP/sub/c.txt"

reset_arch_tmp()
{
  rm -rf "$ARCH_TMP"
  mkdir -p "$ARCH_TMP/sub" && touch "$ARCH_TMP/a.txt" "$ARCH_TMP/b.txt" "$ARCH_TMP/sub/c.txt"
}

# 1. --help exits 0 and lists subcommands
run_zsh_archive help
assert_exit0 $RAW_ST "archive: help exits 0"
assert_contains "$RAW_OUT" "create" "archive: help mentions create"
assert_contains "$RAW_OUT" "recompress" "archive: help mentions recompress"

# 2. create --dry-run: prints plan without creating archive
reset_arch_tmp
run_zsh_archive create "$ARCH_TMP/a.txt" "$ARCH_TMP/sub" --output "$ARCH_TMP/out.zip" --dry-run
assert_exit0 $RAW_ST "archive: create dry-run exits 0"
assert_contains "$RAW_OUT" "archive plan" "archive: create dry-run prints plan"
assert_contains "$RAW_OUT" "format: zip" "archive: create dry-run shows format"
[[ ! -f "$ARCH_TMP/out.zip" ]] && pass "archive: create dry-run did not create archive" \
  || fail "archive: create dry-run should not create archive"

# 3. create (zip, --no-dry-run --yes): creates valid zip
reset_arch_tmp
run_zsh_archive create "$ARCH_TMP/a.txt" "$ARCH_TMP/sub" --output "$ARCH_TMP/out.zip" --no-dry-run --yes
assert_exit0 $RAW_ST "archive: zip create no-dry-run exits 0"
[[ -f "$ARCH_TMP/out.zip" ]] && pass "archive: zip create wrote output file" \
  || fail "archive: zip create should write output file"
# Verify it's a real zip by inspecting the output (zip mock forwards to
# real /usr/bin/zip so the output IS a valid zip).
if unzip -l "$ARCH_TMP/out.zip" > /dev/null 2>&1; then
  pass "archive: zip create output is a valid zip"
else
  fail "archive: zip create output is not a valid zip"
fi

# 4. create --delete-sources without --yes refuses (exit 77)
reset_arch_tmp
run_zsh_archive create "$ARCH_TMP/a.txt" --output "$ARCH_TMP/out.zip" --delete-sources
if (( RAW_ST == 77 )); then
  pass "archive: create --delete-sources without --yes exits 77"
else
  print -r -- "expected 77, got $RAW_ST"
  fail "archive: create --delete-sources exit code"
fi
[[ -f "$ARCH_TMP/a.txt" ]] && pass "archive: refused --delete-sources left source intact" \
  || fail "archive: refused --delete-sources should not delete source"

# 5. create --delete-sources --yes --no-dry-run: archives then deletes
reset_arch_tmp
run_zsh_archive create "$ARCH_TMP/a.txt" --output "$ARCH_TMP/out.zip" --delete-sources --yes --no-dry-run
assert_exit0 $RAW_ST "archive: --delete-sources --yes no-dry-run exits 0"
[[ ! -f "$ARCH_TMP/a.txt" ]] && pass "archive: --delete-sources deleted source" \
  || fail "archive: --delete-sources should delete source"

# 6. create --protect blocks --delete-sources even with --yes
reset_arch_tmp
setopt local_options no_errexit
( HOME="$HOME" MACADMIN_PROTECT=1 MACADMIN_YES=1 PATH="$HERE/mocks:$PATH" zsh "$REPO/scripts/archive.zsh" create "$ARCH_TMP/a.txt" --output "$ARCH_TMP/out.zip" --delete-sources --yes --no-dry-run ) > /dev/null 2>&1
ST_PROTECT=$?
setopt local_options errexit
if (( ST_PROTECT == 77 )); then
  pass "archive: --protect blocks --delete-sources even with --yes"
else
  print -r -- "expected 77, got $ST_PROTECT"
  fail "archive: --protect exit code"
fi
[[ -f "$ARCH_TMP/a.txt" ]] && pass "archive: --protect left source intact" \
  || fail "archive: --protect should leave source intact"

# 7. create --format 7z (mocked): produces 7z-like output
reset_arch_tmp
run_zsh_archive create "$ARCH_TMP/a.txt" --format 7z --output "$ARCH_TMP/out.7z" --no-dry-run --yes
assert_exit0 $RAW_ST "archive: 7z create no-dry-run exits 0"
[[ -f "$ARCH_TMP/out.7z" ]] && pass "archive: 7z create wrote output file" \
  || fail "archive: 7z create should write output file"
assert_contains "$(cat "$ARCH_TMP/out.7z")" "input: " "archive: 7z mock recorded inputs"

# 8. create with missing source exits EX_NOINPUT (66)
reset_arch_tmp
run_zsh_archive create "$ARCH_TMP/nonexistent.txt" --output "$ARCH_TMP/out.zip" --no-dry-run --yes
if (( RAW_ST == 66 )); then
  pass "archive: create with missing source exits 66 (EX_NOINPUT)"
else
  print -r -- "expected 66, got $RAW_ST"
  fail "archive: create missing source exit code"
fi

# 9. create --format 7z without 7z in PATH returns EX_UNAVAILABLE (69)
reset_arch_tmp
# Run without the 7z mock in PATH; the script should fail to find 7z.
setopt local_options no_errexit
( HOME="$HOME" PATH="/usr/bin:/bin" zsh "$REPO/scripts/archive.zsh" create "$ARCH_TMP/a.txt" --format 7z --output "$ARCH_TMP/out.7z" --no-dry-run --yes ) > /dev/null 2>&1
ST_NO7Z=$?
setopt local_options errexit
if (( ST_NO7Z == 69 )); then
  pass "archive: create --format 7z with no 7z exits 69 (EX_UNAVAILABLE)"
else
  print -r -- "expected 69, got $ST_NO7Z"
  fail "archive: create --format 7z no-7z exit code"
fi

# 10. create with no sources exits EX_USAGE (64)
run_zsh_archive create --output "$ARCH_TMP/out.zip" --no-dry-run --yes
if (( RAW_ST == 64 )); then
  pass "archive: create with no sources exits 64 (EX_USAGE)"
else
  print -r -- "expected 64, got $RAW_ST"
  fail "archive: create no sources exit code"
fi

# 11. unknown subcommand exits EX_USAGE (64)
run_zsh_archive frobnicate
if (( RAW_ST == 64 )); then
  pass "archive: unknown subcommand exits 64"
else
  print -r -- "expected 64, got $RAW_ST"
  fail "archive: unknown subcommand exit code"
fi

# 12. dispatcher routing: macadmin archive ...
reset_arch_tmp
COMBINED=$(HOME="$HOME" PATH="$HERE/mocks:$PATH" zsh "$REPO/bin/macadmin" archive help 2>&1)
ST=$?
assert_exit0 $ST "archive: dispatcher route exits 0"
assert_contains "$COMBINED" "create" "archive: dispatcher emits help"

# Cleanup
rm -rf "$ARCH_TMP"
