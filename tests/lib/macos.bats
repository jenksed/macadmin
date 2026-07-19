#!/usr/bin/env bats
#
# tests/lib/macos.bats
# Tests for lib/macos.zsh macOS helpers.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  LIB_DIR="${REPO_ROOT}/lib"
}

@test "macadmin_arch returns arm64 or x86_64" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_arch")"
  [ "$result" = "arm64" ] || [ "$result" = "x86_64" ]
}

@test "macadmin_is_apple_silicon and macadmin_is_intel are mutually exclusive" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_is_apple_silicon && echo silicon || echo intel")"
  [ "$result" = "silicon" ] || [ "$result" = "intel" ]
}

@test "macadmin_macos_version returns semver" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_macos_version")"
  [[ "$result" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
}

@test "macadmin_macos_major is a number" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_macos_major")"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "macadmin_macos_minor is a number" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_macos_minor")"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "macadmin_macos_at_least: high target returns false" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_macos_at_least 999 && echo true || echo false")"
  [ "$result" = "false" ]
}

@test "macadmin_macos_at_least: low target returns true" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_macos_at_least 1 && echo true || echo false")"
  [ "$result" = "true" ]
}

@test "macadmin_hostname returns non-empty" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_hostname")"
  [ -n "$result" ]
}

@test "macadmin_current_user returns non-empty" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_current_user")"
  [ -n "$result" ]
}

@test "macadmin_user_home matches HOME" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_user_home")"
  [ "$result" = "$HOME" ]
}

@test "macadmin_disk_usage_pct is a number" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_disk_usage_pct")"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "macadmin_free_memory_bytes is a number" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_free_memory_bytes")"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "macadmin_list_system_caches includes HOME/Library/Caches" {
  result="$(zsh -c "source '${LIB_DIR}/macos.zsh' && macadmin_list_system_caches")"
  [[ "$result" == *"$HOME/Library/Caches"* ]]
}