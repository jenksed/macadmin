#!/usr/bin/env zsh
# shellcheck shell=bash
# macadmin installer.
# Usage:
#   ./install.sh                 # install to ~/.macadmin, symlink to ~/bin/macadmin
#   ./install.sh --dir <path>    # install to <path> (must be under $HOME)
#   ./install.sh --uninstall     # remove installed artifacts
#   ./install.sh --help
#
# This script never deletes arbitrary paths. --dir is rejected unless it is
# an existing directory under $HOME.

emulate -L zsh
set -o errexit -o nounset -o pipefail

# ----- Paths ---------------------------------------------------------------

readonly DEFAULT_INSTALL_DIR="${HOME}/.macadmin"
readonly BIN_LINK="${HOME}/bin/macadmin"
readonly RC_FILE="${HOME}/.zshrc"
readonly PATH_MARKER='# macadmin PATH'

# ----- Logging -------------------------------------------------------------

if [[ -t 1 ]]; then
  readonly C_RED=$'\e[31m'
  readonly C_GREEN=$'\e[32m'
  readonly C_YELLOW=$'\e[33m'
  readonly C_BLUE=$'\e[34m'
  readonly C_DIM=$'\e[2m'
  readonly C_RESET=$'\e[0m'
else
  readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM='' C_RESET=''
fi

info()  { print -r -- "${C_BLUE}[INFO]${C_RESET} $*"; }
ok()    { print -r -- "${C_GREEN}[OK]${C_RESET} $*"; }
warn()  { print -r -- "${C_YELLOW}[WARN]${C_RESET} $*" >&2; }
err()   { print -r -- "${C_RED}[ERROR]${C_RESET} $*" >&2; }

# ----- Help ----------------------------------------------------------------

usage() {
  cat <<'EOF'
macadmin installer

Usage:
  install.sh [--dir <path>] [--uninstall] [--no-link] [--no-rc] [--help]

Options:
  --dir <path>   Install directory. Defaults to ~/.macadmin.
                 Must be under $HOME and must exist or be creatable.
  --uninstall    Remove installed artifacts (symlink, optionally dir).
  --no-link      Skip creating the symlink in ~/bin.
  --no-rc        Skip appending PATH to ~/.zshrc.
  --help         Show this help.

Examples:
  ./install.sh
  ./install.sh --dir "$HOME/work/macadmin"
  ./install.sh --uninstall
EOF
}

# ----- Argument parsing ----------------------------------------------------

INSTALL_DIR="$DEFAULT_INSTALL_DIR"
UNINSTALL=0
DO_LINK=1
DO_RC=1

while (( $# > 0 )); do
  case "$1" in
    --dir)
      [[ -n "${2:-}" ]] || { err "--dir requires a path"; exit 64; }
      INSTALL_DIR="$2"
      shift 2
      ;;
    --uninstall) UNINSTALL=1; shift ;;
    --no-link)   DO_LINK=0; shift ;;
    --no-rc)     DO_RC=0; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)
      err "unknown option: $1"
      usage >&2
      exit 64
      ;;
  esac
done

# ----- Pre-flight ----------------------------------------------------------

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "macadmin requires macOS"
  exit 69
fi

if ! command -v zsh >/dev/null 2>&1; then
  err "zsh is required but not found in PATH"
  exit 69
fi

if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found; install with: brew install jq"
fi

# Locate source directory (this script's directory).
if [[ -n "${ZSH_VERSION:-}" ]] && [[ -n "${(%):-%N:-}" ]]; then
  SOURCE_DIR="${${(%):-%N}:A:h}"
else
  SOURCE_DIR="$(cd "$(dirname -- "$0")" && pwd)"
fi

# ----- Uninstall -----------------------------------------------------------

if (( UNINSTALL )); then
  info "Uninstalling macadmin..."
  if [[ -L "$BIN_LINK" ]]; then
    rm -f -- "$BIN_LINK"
    ok "Removed symlink: $BIN_LINK"
  fi
  if [[ -d "$INSTALL_DIR" ]]; then
    if [[ "$INSTALL_DIR" == "${HOME}/"* ]]; then
      warn "Install directory still present: $INSTALL_DIR"
      warn "Delete manually with: rm -rf -- '$INSTALL_DIR'"
    else
      warn "Refusing to touch install dir outside \$HOME: $INSTALL_DIR"
    fi
  fi
  info "Uninstall complete."
  exit 0
fi

# ----- Validate install dir ------------------------------------------------

# Reject empty, root, system, or non-$HOME paths.
case "$INSTALL_DIR" in
  ""|"/"|"/System"*|"/usr"*|"/bin"*|"/sbin"*|"/lib"*|"/etc"*|"/var"*|"/private"*|"/tmp")
    err "refusing to install into system path: $INSTALL_DIR"
    exit 78
    ;;
esac

if [[ "$INSTALL_DIR" != "${HOME}/"* ]]; then
  err "--dir must be under \$HOME (got: $INSTALL_DIR)"
  err "pass --dir \"\$HOME/...\" or omit --dir to use the default"
  exit 78
fi

# Ensure absolute path.
INSTALL_DIR="${INSTALL_DIR:A}"
readonly INSTALL_DIR

# If INSTALL_DIR is the source directory, copy into a sibling.
if [[ "$INSTALL_DIR" == "$SOURCE_DIR" ]]; then
  warn "Source directory equals install directory; copying source into itself is a no-op"
  warn "Proceeding without copying."
  DID_COPY=0
elif [[ -d "$INSTALL_DIR" ]]; then
  info "Install directory already exists: $INSTALL_DIR"
  info "Copying current source on top (will not delete existing files)."
  DID_COPY=1
  cp -R -- "$SOURCE_DIR/." "$INSTALL_DIR/"
else
  info "Creating install directory: $INSTALL_DIR"
  mkdir -p -- "$INSTALL_DIR"
  cp -R -- "$SOURCE_DIR/." "$INSTALL_DIR/"
  DID_COPY=1
fi

# ----- Initialize user config ---------------------------------------------

if [[ ! -f "${HOME}/.macadminrc" ]] && [[ -f "$INSTALL_DIR/share/macadminrc.example" ]]; then
  cp -- "$INSTALL_DIR/share/macadminrc.example" "${HOME}/.macadminrc"
  ok "Created ~/.macadminrc from example"
fi

if [[ ! -f "${HOME}/.macadminignore" ]]; then
  : > "${HOME}/.macadminignore"
  ok "Created empty ~/.macadminignore"
fi

# ----- Symlink to ~/bin ----------------------------------------------------

if (( DO_LINK )); then
  if [[ ! -d "${HOME}/bin" ]]; then
    info "Creating ${HOME}/bin"
    mkdir -p -- "${HOME}/bin"
  fi
  if [[ -e "$BIN_LINK" ]] && [[ ! -L "$BIN_LINK" ]]; then
    err "$BIN_LINK exists and is not a symlink; refusing to overwrite"
    err "remove it manually or pass --no-link"
    exit 73
  fi
  rm -f -- "$BIN_LINK"
  ln -s -- "$INSTALL_DIR/bin/macadmin" "$BIN_LINK"
  ok "Symlinked: $BIN_LINK -> $INSTALL_DIR/bin/macadmin"
fi

# ----- Append PATH to ~/.zshrc ---------------------------------------------

if (( DO_RC )); then
  if [[ ! -f "$RC_FILE" ]]; then
    : > "$RC_FILE"
  fi
  if ! grep -qF "$PATH_MARKER" "$RC_FILE" 2>/dev/null; then
    {
      print -r -- ""
      print -r -- "$PATH_MARKER"
      print -r -- 'export PATH="$HOME/bin:$PATH"'
    } >> "$RC_FILE"
    ok "Added PATH to $RC_FILE"
  else
    info "PATH already configured in $RC_FILE"
  fi
fi

# ----- Verify install ------------------------------------------------------

info "Verifying install..."
if ! command -v zsh >/dev/null 2>&1; then
  err "zsh missing post-install"
  exit 70
fi

# help exits 0 with a non-empty command list
HELP_OUT=$(zsh "$INSTALL_DIR/bin/macadmin" help 2>&1) || {
  err "macadmin help failed post-install:"
  print -r -- "$HELP_OUT" >&2
  exit 70
}
HELP_LINES=$(print -r -- "$HELP_OUT" | wc -l | tr -d ' ')
if (( HELP_LINES < 5 )); then
  err "macadmin help produced suspiciously short output ($HELP_LINES lines)"
  exit 70
fi

# system-info --json must emit valid JSON if jq is available
if command -v jq >/dev/null 2>&1; then
  JSON_OUT=$(zsh "$INSTALL_DIR/bin/macadmin" system-info --json 2>&1) || {
    err "macadmin system-info --json failed post-install"
    print -r -- "$JSON_OUT" >&2
    exit 70
  }
  if ! print -r -- "$JSON_OUT" | jq . >/dev/null 2>&1; then
    err "macadmin system-info --json did not emit valid JSON"
    print -r -- "$JSON_OUT" >&2
    exit 70
  fi
  ok "macadmin system-info --json emits valid JSON"
fi

# ----- Done ----------------------------------------------------------------

print -r -- ""
print -r -- "${C_GREEN}macadmin installed successfully.${C_RESET}"
print -r -- ""
print -r -- "  Location:    $INSTALL_DIR"
print -r -- "  Config:      ${HOME}/.macadminrc"
print -r -- "  Ignore file: ${HOME}/.macadminignore"
if (( DO_LINK )); then
  print -r -- "  Symlink:     $BIN_LINK"
fi
print -r -- ""
print -r -- "  Try:         macadmin help"
print -r -- "  Uninstall:   ${INSTALL_DIR}/install.sh --uninstall"
if (( DO_RC )); then
  print -r -- "  Restart your shell or run: source ${RC_FILE}"
fi
print -r -- ""