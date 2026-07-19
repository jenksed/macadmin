#!/usr/bin/env bats
#
# tests/lib/config.bats
# Tests for lib/config.zsh config loader.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  LIB_DIR="${REPO_ROOT}/lib"
}

@test "macadmin_config_path defaults to ~/.macadminrc" {
  result="$(zsh -c "source '${LIB_DIR}/config.zsh' && unset MACADMIN_CONFIG && macadmin_config_path")"
  [ "$result" = "$HOME/.macadminrc" ]
}

@test "macadmin_config_path honors MACADMIN_CONFIG override" {
  result="$(zsh -c "source '${LIB_DIR}/config.zsh' && MACADMIN_CONFIG=/tmp/foo && macadmin_config_path")"
  [ "$result" = "/tmp/foo" ]
}

@test "macadmin_config_load: missing file is OK" {
  result="$(zsh -c "source '${LIB_DIR}/config.zsh' && MACADMIN_CONFIG=/nonexistent-xyz && macadmin_config_load && echo ok")"
  [ "$result" = "ok" ]
}

@test "macadmin_config_load: loads UPPER_CASE keys" {
  CFG=$(mktemp)
  cat > "$CFG" <<EOF
FOO_TEST=bar_value
BAZ_TEST=qux_value
EOF
  result=$(zsh -c "source '${LIB_DIR}/config.zsh' && MACADMIN_CONFIG='$CFG' && macadmin_config_load && print -r -- \"\$FOO_TEST:\$BAZ_TEST\"")
  rm -f "$CFG"
  [ "$result" = "bar_value:qux_value" ]
}

@test "macadmin_config_load: ignores lowercase keys" {
  CFG=$(mktemp)
  cat > "$CFG" <<EOF
lowercase=value
UPPERCASE=value2
EOF
  result=$(zsh -c "source '${LIB_DIR}/config.zsh' && MACADMIN_CONFIG='$CFG' && macadmin_config_load && print -r -- \"\${lowercase:-empty}:\${UPPERCASE:-empty}\"")
  rm -f "$CFG"
  [ "$result" = "empty:value2" ]
}

@test "macadmin_config_get: returns value when set" {
  CFG=$(mktemp)
  printf 'TEST_KEY=hello\n' > "$CFG"
  result=$(zsh -c "source '${LIB_DIR}/config.zsh' && MACADMIN_CONFIG='$CFG' && unset __MACADMIN_CONFIG_LOADED && macadmin_config_get TEST_KEY default")
  rm -f "$CFG"
  [ "$result" = "hello" ]
}

@test "macadmin_config_get: returns default when unset" {
  result=$(zsh -c "source '${LIB_DIR}/config.zsh' && MACADMIN_CONFIG=/nonexistent-xyz && unset __MACADMIN_CONFIG_LOADED && macadmin_config_get MISSING_KEY fallback")
  [ "$result" = "fallback" ]
}