#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
emulate -L zsh
set -o errexit -o nounset -o pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
source "$SCRIPT_DIR/../lib/argparse.zsh" 2>/dev/null || true
macadmin_parse_globals "$@" 2>/dev/null || true
set -- "${MACADMIN_ARGS[@]:-}"
require_macos || exit 1

usage() {
  cat <<'EOF'
brew_tools.zsh - Homebrew helpers

Usage:
  brew_tools.zsh check
  brew_tools.zsh ensure [--yes] [--dry-run]
  brew_tools.zsh bundle --generate
  brew_tools.zsh bundle --diff
  brew_tools.zsh bundle --apply [--dry-run]

Notes:
  - ensure: detects Homebrew; installs only with --yes. Prints next steps.
  - bundle --generate: create Brewfile in CWD (overwrites).
  - bundle --diff: show changes vs current system (missing/removals).
  - bundle --apply: apply Brewfile (respects --dry-run; prints plan).
  - Apple Silicon vs Intel handled by brew path (/opt/homebrew vs /usr/local).
EOF
}

_arch() { uname -m 2>/dev/null || echo ""; }
_brew_prefix_guess() {
  local m; m=$(_arch)
  if [[ "$m" == arm64* ]]; then echo "/opt/homebrew"; else echo "/usr/local"; fi
}

_brew_info_json() {
  local found=0 path="" ver=""
  if command -v brew >/dev/null 2>&1; then
    found=1
    path=$(command -v brew)
    ver=$(brew --version 2>/dev/null | head -1)
  fi
  macadmin_json_obj found=$([[ $found -eq 1 ]] && echo true || echo false) path="$path" version="$ver" arch="$(_arch)" prefix_guess="$(_brew_prefix_guess)"
  printf '
'
}

cmd=${1:-}
case "$cmd" in
  -h|--help|help|"") usage; exit 0 ;;

  check)
    if command -v brew >/dev/null 2>&1; then
      local v; v=$(brew --version | head -1)
      if (( MACADMIN_JSON )); then
        macadmin_json_obj event="brew_detect" found=true version="$v" path="$(command -v brew)"; printf '
'
      else
        log_info "Homebrew found: $v"
      fi
      exit 0
    else
      if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_detect" found=false; printf '
'; fi
      log_warn "Homebrew not installed."
      exit ${EX_UNAVAILABLE:-69}
    fi
    ;;

  ensure)
    if command -v brew >/dev/null 2>&1; then
      local v; v=$(brew --version | head -1)
      if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_present" version="$v" path="$(command -v brew)"; printf '
'; else log_info "Homebrew already installed ($v)."; fi
      print -r -- "Next: manage packages using 'brew bundle' with a Brewfile." 2>/dev/null || true
      exit 0
    fi

    # Not installed: require --yes; respect dry-run
    if (( ! MACADMIN_YES )); then
      log_error "Refusing to install Homebrew without --yes."
      exit ${EX_NOPERM:-77}
    fi

    local prefix; prefix=$(_brew_prefix_guess)
    local install_cmd="/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""
    if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_install_plan" prefix="$prefix" arch="$(_arch)"; printf '
'; else log_info "Planned Homebrew install to $prefix (arch: $(_arch))."; fi
    if (( MACADMIN_DRY_RUN )); then
      log_info "Dry-run: would run: $install_cmd"
      exit 0
    fi
    log_info "Installing Homebrew..."
    # Clear prompt before network call (non-interactive when --yes provided)
    print -r -- "Proceeding with non-interactive install (requested with --yes)."
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if command -v brew >/dev/null 2>&1; then
      if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_install_done" ok=true path="$(command -v brew)"; printf '
'; else success "Homebrew installed."; fi
      print -r -- "Next: run 'brew bundle' in a directory with a Brewfile."
      exit 0
    else
      log_error "Homebrew installation did not complete successfully."
      exit ${EX_SOFTWARE:-70}
    fi
    ;;

  bundle)
    require_cmd brew || { log_error "brew not available"; exit ${EX_UNAVAILABLE:-69}; }
    local mode=""
    case "${2:-}" in
      --generate) mode=generate ;;
      --diff) mode=diff ;;
      --apply) mode=apply ;;
      "") mode=legacy ;;
      *) log_error "Unknown bundle flag: ${2:-}"; usage; exit ${EX_USAGE:-64} ;;
    esac

    case "$mode" in
      legacy)
        # Back-compat: run bundle directly
        if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_bundle_legacy" cwd="$PWD"; printf '
'; fi
        log_info "Running brew bundle in $PWD..."
        run brew bundle
        ;;
      generate)
        local f="$PWD/Brewfile"
        if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_bundle_generate" file="$f"; printf '
'; else log_info "Generating Brewfile at $f (overwrite)."; fi
        if (( MACADMIN_DRY_RUN )); then
          log_info "Dry-run: would run: brew bundle dump --force --file Brewfile"
        else
          run brew bundle dump --force --file Brewfile
        fi
        ;;
      diff)
        if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_bundle_diff_start" cwd="$PWD"; printf '
'; else log_info "Computing differences vs Brewfile..."; fi
        # Missing items
        run brew bundle check --verbose || true
        # Removals (what would be cleaned up)
        run brew bundle cleanup --dry-run || true
        if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_bundle_diff_done" ok=true; printf '
'; fi
        ;;
      apply)
        if (( MACADMIN_JSON )); then macadmin_json_obj event="brew_bundle_apply" cwd="$PWD"; printf '
'; else log_info "Applying Brewfile..."; fi
        if (( MACADMIN_DRY_RUN )); then
          log_info "Dry-run: would run: brew bundle"
        else
          run brew bundle
        fi
        ;;
    esac
    ;;

  *) usage; exit 0 ;;

esac

log_info "Done."
