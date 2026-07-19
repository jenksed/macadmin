#!/usr/bin/env bats
#
# tests/lib/paths.bats
# Tests for lib/paths.zsh path accessors.
# Bats runs under bash; lib/paths.zsh uses zsh-only features, so each
# test invokes zsh explicitly.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  LIB_DIR="${REPO_ROOT}/lib"
}

@test "macadmin_path_user_home returns HOME" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_user_home")"
  [ "$result" = "$HOME" ]
}

@test "macadmin_path_user_cache is HOME/Library/Caches" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_user_cache")"
  [ "$result" = "$HOME/Library/Caches" ]
}

@test "macadmin_path_user_logs is HOME/Library/Logs" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_user_logs")"
  [ "$result" = "$HOME/Library/Logs" ]
}

@test "macadmin_path_xcode_derived_data is HOME/Library/Developer/Xcode/DerivedData" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_xcode_derived_data")"
  [ "$result" = "$HOME/Library/Developer/Xcode/DerivedData" ]
}

@test "macadmin_path_npm_cache is HOME/.npm/_cacache" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_npm_cache")"
  [ "$result" = "$HOME/.npm/_cacache" ]
}

@test "macadmin_path_docker_logs ends with Data/log" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_docker_logs")"
  [[ "$result" == *"/Data/log" ]]
}

@test "macadmin_path_system_cache is /Library/Caches" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_system_cache")"
  [ "$result" = "/Library/Caches" ]
}

@test "macadmin_path_config defaults to ~/.macadminrc" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && unset MACADMIN_CONFIG && macadmin_path_config")"
  [ "$result" = "$HOME/.macadminrc" ]
}

@test "macadmin_path_config honors MACADMIN_CONFIG override" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && MACADMIN_CONFIG=/tmp/foo && macadmin_path_config")"
  [ "$result" = "/tmp/foo" ]
}

@test "macadmin_path_ignore defaults to ~/.macadminignore" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && unset MACADMIN_IGNORE_FILE && macadmin_path_ignore")"
  [ "$result" = "$HOME/.macadminignore" ]
}

@test "macadmin_path_abs resolves to absolute (zsh :A modifier)" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_abs .")"
  [ "$result" = "$PWD" ]
}

@test "macadmin_path_is_dir returns 0 for existing dir" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_is_dir '$HOME' && echo yes || echo no")"
  [ "$result" = "yes" ]
}

@test "macadmin_path_is_dir returns 1 for missing dir" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && macadmin_path_is_dir /nonexistent-path-xyz && echo yes || echo no")"
  [ "$result" = "no" ]
}

@test "sourcing paths.zsh twice is idempotent" {
  result="$(zsh -c "source '${LIB_DIR}/paths.zsh' && source '${LIB_DIR}/paths.zsh' && macadmin_path_user_home")"
  [ "$result" = "$HOME" ]
}