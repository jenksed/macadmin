#!/usr/bin/env bats
#
# tests/lib/io.bats
# Tests for lib/io.zsh file I/O helpers.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  LIB_DIR="${REPO_ROOT}/lib"
}

@test "macadmin_io_safe_rm: missing file returns 1" {
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_safe_rm /nonexistent-xyz; echo \$?")"
  [ "$result" = "1" ]
}

@test "macadmin_io_safe_rm: refuses /etc/passwd" {
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_safe_rm /etc/passwd; echo \$?")"
  [ "$result" = "2" ]
}

@test "macadmin_io_safe_rm: removes HOME test file" {
  TMP=$(mktemp -d)
  echo "x" > "$TMP/del.txt"
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_safe_rm '$TMP/del.txt' && echo ok")"
  [ "$result" = "ok" ]
  [ ! -e "$TMP/del.txt" ]
  rm -rf "$TMP"
}

@test "macadmin_io_safe_rm: dry-run does not delete" {
  TMP=$(mktemp -d)
  echo "x" > "$TMP/del.txt"
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && MACADMIN_DRY_RUN=1 macadmin_io_safe_rm '$TMP/del.txt' && echo ok")"
  [ "$result" = "ok" ]
  [ -e "$TMP/del.txt" ]
  rm -rf "$TMP"
}

@test "macadmin_io_backup_file: missing source returns 1" {
  TMP=$(mktemp -d)
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_backup_file /nonexistent-xyz '$TMP'; echo \$?")"
  [ "$result" = "1" ]
  rm -rf "$TMP"
}

@test "macadmin_io_backup_file: copies with timestamp" {
  TMP=$(mktemp -d)
  echo "hello" > "$TMP/file.txt"
  out=$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_backup_file '$TMP/file.txt' '$TMP/backup'")
  [ -f "$out" ]
  [ "$(cat "$out")" = "hello" ]
  rm -rf "$TMP"
}

@test "macadmin_io_temp_dir: idempotent" {
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && eval \"\$(macadmin_io_temp_dir)\" && d1=\$MACADMIN_TEMP_DIR && eval \"\$(macadmin_io_temp_dir)\" && d2=\$MACADMIN_TEMP_DIR && [ \"\$d1\" = \"\$d2\" ] && echo same || echo different")"
  [ "$result" = "same" ]
}

@test "macadmin_io_temp_cleanup: clears dir" {
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && eval \"\$(macadmin_io_temp_dir)\" && d=\$MACADMIN_TEMP_DIR && macadmin_io_temp_cleanup && unset MACADMIN_TEMP_DIR && [ ! -d \"\$d\" ] && echo cleared || echo still-here")"
  [ "$result" = "cleared" ]
}

@test "macadmin_io_atomic_write: creates file with content" {
  TMP=$(mktemp -d)
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_atomic_write '$TMP/out.txt' 'hello world' && cat '$TMP/out.txt'")"
  [ "$result" = "hello world" ]
  rm -rf "$TMP"
}

@test "macadmin_io_atomic_write: handles newlines" {
  TMP=$(mktemp -d)
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_atomic_write '$TMP/out.txt' \$'line1\nline2\nline3' && cat '$TMP/out.txt'")"
  [ "$result" = $'line1\nline2\nline3' ]
  rm -rf "$TMP"
}

@test "macadmin_io_atomic_write: creates parent directory" {
  TMP=$(mktemp -d)
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_atomic_write '$TMP/sub/dir/out.txt' 'nested' && cat '$TMP/sub/dir/out.txt'")"
  [ "$result" = "nested" ]
  rm -rf "$TMP"
}

@test "macadmin_io_read_lines: skips blanks and comments" {
  TMP=$(mktemp -d)
  printf 'first\n# comment\n\nsecond\n' > "$TMP/in.txt"
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_read_lines '$TMP/in.txt' | wc -l | tr -d ' '")"
  [ "$result" = "2" ]
  rm -rf "$TMP"
}

@test "macadmin_io_read_lines: missing file returns 1" {
  result="$(zsh -c "source '${LIB_DIR}/io.zsh' && macadmin_io_read_lines /nonexistent-xyz; echo \$?")"
  [ "$result" = "1" ]
}