#!/usr/bin/env zsh
# tests/test_files.zsh — Release 0.5 files.zsh tests.
# Covers 'rename', 'sort', 'organize screenshots' with their safety gates.
#
# Convention: invoke each command via a fresh tmp dir under $HOME/Downloads
# (which satisfies ALL three safety checks: rename+organize need $HOME,
# sort needs $HOME/Downloads/Desktop/Documents allowlist).
#
# Capture pattern: temp file for stdout+stderr + setopt local_options
# no_errexit around the inner command so errexit doesn't trip on
# non-zero exit codes. Sets RAW_OUT and RAW_ST globals (similar to
# assert.zsh's R_OUT/R_STATUS convention).
emulate -L zsh
setopt errexit nounset pipefail

HERE=${0:a:h}
REPO="$HERE/.."
source "$HERE/assert.zsh"

# Test root lives under $HOME/Downloads so all three subcommands accept it.
FILES_TEST_ROOT="$HOME/Downloads/macadmin_test_$$"
rm -rf "$FILES_TEST_ROOT"
mkdir -p "$FILES_TEST_ROOT"

reset_test_dir()
{
  rm -rf "$FILES_TEST_ROOT"
  mkdir -p "$FILES_TEST_ROOT"
}

# Run files.zsh inside $cwd with [args]. Sets globals RAW_OUT (combined
# stdout+stderr) and RAW_ST (exit code). Uses a temp file + local
# errexit suppression so the capture pattern is safe even when the
# inner command exits non-zero (e.g. safety gates).
run_zsh_files()
{
  local cwd="$1"; shift
  local rawf="/tmp/.macadmin_test_$$_$RANDOM"
  setopt local_options no_errexit
  ( cd "$cwd" && HOME="$HOME" PATH="$HERE/mocks:$PATH" zsh "$REPO/scripts/files.zsh" "$@" ) > "$rawf" 2>&1
  RAW_ST=$?
  RAW_OUT=$(cat "$rawf")
  rm -f "$rawf"
}

# Run a files.zsh invocation that REQUIRES --yes (or --protect) for the
# safety gate. Uses a direct subshell + $? capture with errexit suppressed
# locally so the script doesn't bail on non-zero exit. Sets RAW_OK.
# $1 = cwd, $2+ = args.
run_zsh_files_unsafe()
{
  local cwd="$1"; shift
  setopt local_options no_errexit
  ( cd "$cwd" && HOME="$HOME" PATH="$HERE/mocks:$PATH" MACADMIN_YES=1 zsh "$REPO/scripts/files.zsh" "$@" ) > /dev/null 2>&1
  RAW_OK=$?
  setopt local_options errexit
}

# 1. --help exits 0 and lists subcommands
run_zsh_files "$REPO" help
assert_exit0 $RAW_ST "files: help exits 0"
assert_contains "$RAW_OUT" "rename" "files: help mentions rename"
assert_contains "$RAW_OUT" "sort" "files: help mentions sort"
assert_contains "$RAW_OUT" "organize" "files: help mentions organize"

# 2. rename dry-run: shows plan without renaming
reset_test_dir
mkdir -p "$FILES_TEST_ROOT/rename_test"
touch "$FILES_TEST_ROOT/rename_test/a.txt" "$FILES_TEST_ROOT/rename_test/b.txt" "$FILES_TEST_ROOT/rename_test/c.txt"
run_zsh_files "$FILES_TEST_ROOT/rename_test" rename "*.txt" --prefix "old_" --dry-run
assert_exit0 $RAW_ST "files: rename dry-run exits 0"
assert_contains "$RAW_OUT" "rename: a.txt" "files: rename dry-run shows a.txt"
assert_contains "$RAW_OUT" "rename: b.txt" "files: rename dry-run shows b.txt"
[[ -f "$FILES_TEST_ROOT/rename_test/a.txt" ]] && pass "files: rename dry-run did not actually rename" \
  || fail "files: rename dry-run should not rename"

# 3. rename --no-dry-run without --yes refuses (exit 77)
reset_test_dir
mkdir -p "$FILES_TEST_ROOT/rename_test" && touch "$FILES_TEST_ROOT/rename_test/a.txt"
run_zsh_files "$FILES_TEST_ROOT/rename_test" rename "*.txt" --prefix "new_" --no-dry-run
if (( RAW_ST == 77 )); then
  pass "files: rename --no-dry-run without --yes exits 77"
else
  print -r -- "expected 77, got $RAW_ST"
  fail "files: rename --no-dry-run exit code"
fi

# 4. rename --no-dry-run --yes actually renames
reset_test_dir
mkdir -p "$FILES_TEST_ROOT/rename_test" && touch "$FILES_TEST_ROOT/rename_test/a.txt" "$FILES_TEST_ROOT/rename_test/b.txt"
run_zsh_files_unsafe "$FILES_TEST_ROOT/rename_test" rename "*.txt" --prefix "new_" --no-dry-run
assert_exit0 $RAW_OK "files: rename --no-dry-run --yes exits 0"
[[ -f "$FILES_TEST_ROOT/rename_test/new_a.txt" && -f "$FILES_TEST_ROOT/rename_test/new_b.txt" ]] \
  && pass "files: rename --yes actually renamed" \
  || fail "files: rename --yes should rename files"

# 5. rename refuses to operate outside $HOME
reset_test_dir
mkdir -p /tmp/files_outside_home && touch /tmp/files_outside_home/a.txt
run_zsh_files /tmp/files_outside_home rename "*.txt" --prefix "x_" --dry-run
if (( RAW_ST == 77 )); then
  pass "files: rename outside \$HOME exits 77"
else
  print -r -- "expected 77, got $RAW_ST"
  fail "files: rename outside \$HOME exit code"
fi
assert_contains "$RAW_OUT" "refusing to operate outside" "files: rename outside HOME message"

# 6. sort dry-run: shows plan without moving
reset_test_dir
mkdir -p "$FILES_TEST_ROOT/Downloads" && touch "$FILES_TEST_ROOT/Downloads/report.pdf" "$FILES_TEST_ROOT/Downloads/photo.png" "$FILES_TEST_ROOT/Downloads/song.mp3"
run_zsh_files "$FILES_TEST_ROOT/Downloads" sort --path "$FILES_TEST_ROOT/Downloads" --dry-run
assert_exit0 $RAW_ST "files: sort dry-run exits 0"
assert_contains "$RAW_OUT" "Documents" "files: sort plan includes Documents bucket"
assert_contains "$RAW_OUT" "Images" "files: sort plan includes Images bucket"
[[ -f "$FILES_TEST_ROOT/Downloads/report.pdf" ]] && pass "files: sort dry-run did not move files" \
  || fail "files: sort dry-run should not move"

# 7. sort refuses paths outside allowlist
run_zsh_files /tmp sort --path /tmp --dry-run
if (( RAW_ST == 77 )); then
  pass "files: sort outside Downloads/Desktop/Documents exits 77"
else
  print -r -- "expected 77, got $RAW_ST"
  fail "files: sort outside allowlist exit code"
fi
assert_contains "$RAW_OUT" "refusing to operate outside" "files: sort outside allowlist message"

# 8. sort --no-dry-run --yes actually sorts files into subdirs
reset_test_dir
mkdir -p "$FILES_TEST_ROOT/Downloads" && touch "$FILES_TEST_ROOT/Downloads/report.pdf" "$FILES_TEST_ROOT/Downloads/photo.png"
run_zsh_files_unsafe "$FILES_TEST_ROOT/Downloads" sort --path "$FILES_TEST_ROOT/Downloads" --no-dry-run
assert_exit0 $RAW_OK "files: sort --no-dry-run --yes exits 0"
[[ -f "$FILES_TEST_ROOT/Downloads/Documents/report.pdf" ]] \
  && pass "files: sort moved report.pdf to Documents" \
  || fail "files: sort should move report.pdf to Documents"
[[ -f "$FILES_TEST_ROOT/Downloads/Images/photo.png" ]] \
  && pass "files: sort moved photo.png to Images" \
  || fail "files: sort should move photo.png to Images"

# 9. sort --protect blocks --no-dry-run
reset_test_dir
mkdir -p "$FILES_TEST_ROOT/Downloads" && touch "$FILES_TEST_ROOT/Downloads/report.pdf"
setopt local_options no_errexit
ST_OK=$( HOME="$HOME" MACADMIN_PROTECT=1 PATH="$HERE/mocks:$PATH" MACADMIN_YES=1 zsh "$REPO/scripts/files.zsh" sort --path "$FILES_TEST_ROOT/Downloads" --no-dry-run > /dev/null 2>&1; echo $? )
setopt local_options errexit
if (( ST_OK == 77 )); then
  pass "files: sort --protect blocks --no-dry-run"
else
  print -r -- "expected 77, got $ST_OK"
  fail "files: sort --protect exit code"
fi

# 10. organize screenshots dry-run detects screenshots
reset_test_dir
touch "$FILES_TEST_ROOT/Screenshot 2026-07-19 at 10.34.56 AM.png" "$FILES_TEST_ROOT/regular.txt"
run_zsh_files "$FILES_TEST_ROOT" organize screenshots --dest "$FILES_TEST_ROOT/Pictures/Screenshots" --path "$FILES_TEST_ROOT" --dry-run
assert_exit0 $RAW_ST "files: organize screenshots dry-run exits 0"
assert_contains "$RAW_OUT" "Screenshot 2026-07-19" "files: organize detects Screenshot 2026-07-19"
assert_contains "$RAW_OUT" "move:" "files: organize plan includes move action"
[[ -f "$FILES_TEST_ROOT/Screenshot 2026-07-19 at 10.34.56 AM.png" && ! -f "$FILES_TEST_ROOT/Pictures/Screenshots/Screenshot 2026-07-19 at 10.34.56 AM.png" ]] \
  && pass "files: organize dry-run did not move" \
  || fail "files: organize dry-run should not move"

# 11. organize screenshots --no-dry-run --yes actually moves
reset_test_dir
touch "$FILES_TEST_ROOT/Screenshot 2026-07-19 at 10.34.56 AM.png"
run_zsh_files_unsafe "$FILES_TEST_ROOT" organize screenshots --dest "$FILES_TEST_ROOT/Pictures/Screenshots" --path "$FILES_TEST_ROOT" --no-dry-run
assert_exit0 $RAW_OK "files: organize --no-dry-run --yes exits 0"
[[ -f "$FILES_TEST_ROOT/Pictures/Screenshots/Screenshot 2026-07-19 at 10.34.56 AM.png" ]] \
  && pass "files: organize --yes actually moved the screenshot" \
  || fail "files: organize --yes should move"

# 12. organize screenshots --protect blocks
reset_test_dir
touch "$FILES_TEST_ROOT/Screenshot 2026-07-19 at 10.34.56 AM.png"
setopt local_options no_errexit
ST_OK=$( HOME="$HOME" MACADMIN_PROTECT=1 PATH="$HERE/mocks:$PATH" MACADMIN_YES=1 zsh "$REPO/scripts/files.zsh" organize screenshots --dest "$FILES_TEST_ROOT/Pictures/Screenshots" --path "$FILES_TEST_ROOT" --no-dry-run > /dev/null 2>&1; echo $? )
setopt local_options errexit
if (( ST_OK == 77 )); then
  pass "files: organize --protect blocks --no-dry-run"
else
  print -r -- "expected 77, got $ST_OK"
  fail "files: organize --protect exit code"
fi

# 13. dispatcher routing: macadmin files ...
run_zsh_files "$REPO" help
assert_exit0 $RAW_ST "files: dispatcher route exits 0"
assert_contains "$RAW_OUT" "rename" "files: dispatcher emits help"

# Cleanup
rm -rf "$FILES_TEST_ROOT"
