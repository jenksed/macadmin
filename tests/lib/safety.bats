#!/usr/bin/env bats
#
# tests/lib/safety.bats
# Tests for lib/safety.zsh safety primitives.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  LIB_DIR="${REPO_ROOT}/lib"
}

@test "macadmin_safety_path_is_safe: HOME is safe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe '$HOME' && echo yes || echo no")"
  [ "$result" = "yes" ]
}

@test "macadmin_safety_path_is_safe: /etc is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe /etc && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_path_is_safe: /etc/passwd is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe /etc/passwd && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_path_is_safe: /usr/bin is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe /usr/bin && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_path_is_safe: /var is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe /var && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_path_is_safe: /var/log is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe /var/log && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_path_is_safe: /private is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe /private && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_path_is_safe: /private/etc is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe /private/etc && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_path_is_safe: / is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe / && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_path_is_safe: empty is unsafe" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_path_is_safe '' && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_within: /Users/foo/bar in /Users/foo" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_within /Users/foo/bar /Users/foo && echo yes || echo no")"
  [ "$result" = "yes" ]
}

@test "macadmin_safety_within: /etc/passwd not in /Users/foo" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_within /etc/passwd /Users/foo && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "macadmin_safety_within: exact match" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && macadmin_safety_within /Users/foo /Users/foo && echo yes || echo no")"
  [ "$result" = "yes" ]
}

@test "macadmin_safety_protect_gate blocks without --yes" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && MACADMIN_PROTECT=1 MACADMIN_YES=0 macadmin_safety_protect_gate test; echo \$?")"
  [ "$result" = "77" ]
}

@test "macadmin_safety_protect_gate allows with --yes" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && MACADMIN_PROTECT=1 MACADMIN_YES=1 macadmin_safety_protect_gate test; echo \$?")"
  [ "$result" = "0" ]
}

@test "macadmin_safety_protect_gate allows without --protect" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && MACADMIN_PROTECT=0 macadmin_safety_protect_gate test; echo \$?")"
  [ "$result" = "0" ]
}

@test "macadmin_safety_load_ignore: missing file is OK" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && MACADMIN_IGNORE_FILE=/nonexistent && macadmin_safety_load_ignore && echo ok")"
  [ "$result" = "ok" ]
}

@test "macadmin_safety_load_ignore and ignored" {
  result="$(zsh -c "
    source '${LIB_DIR}/safety.zsh'
    IGNORE_TMP=\$(mktemp)
    printf '~/.ssh\nnode_modules\n' > \"\$IGNORE_TMP\"
    MACADMIN_IGNORE_FILE=\"\$IGNORE_TMP\"
    macadmin_safety_load_ignore
    if macadmin_safety_ignored \"\$HOME/.ssh/id_rsa\"; then
      echo ignored
    else
      echo not-ignored
    fi
    rm -f \"\$IGNORE_TMP\"
  ")"
  [ "$result" = "ignored" ]
}

@test "macadmin_safety_ignored: non-matching returns 1" {
  result="$(zsh -c "
    source '${LIB_DIR}/safety.zsh'
    IGNORE_TMP=\$(mktemp)
    printf 'node_modules\n' > \"\$IGNORE_TMP\"
    MACADMIN_IGNORE_FILE=\"\$IGNORE_TMP\"
    macadmin_safety_load_ignore
    if macadmin_safety_ignored '/Users/foo/bar.txt'; then
      echo ignored
    else
      echo not-ignored
    fi
    rm -f \"\$IGNORE_TMP\"
  ")"
  [ "$result" = "not-ignored" ]
}

@test "macadmin_safety_load_ignore skips comments and blanks" {
  result="$(zsh -c "
    source '${LIB_DIR}/safety.zsh'
    IGNORE_TMP=\$(mktemp)
    printf '# comment\n\nnode_modules\n' > \"\$IGNORE_TMP\"
    MACADMIN_IGNORE_FILE=\"\$IGNORE_TMP\"
    macadmin_safety_load_ignore
    print -r -- \"count=\${#_MACADMIN_IGNORE_PATTERNS[@]}\"
    print -r -- \"first=\${_MACADMIN_IGNORE_PATTERNS[1]}\"
    rm -f \"\$IGNORE_TMP\"
  ")"
  [[ "$result" == *"count=1"* ]]
  [[ "$result" == *"first=node_modules"* ]]
}

@test "macadmin_safety_confirm auto-yes with MACADMIN_YES=1" {
  result="$(zsh -c "source '${LIB_DIR}/safety.zsh' && MACADMIN_YES=1 macadmin_safety_confirm test && echo yes || echo no")"
  [ "$result" = "yes" ]
}