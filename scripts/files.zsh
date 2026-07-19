#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
# files.zsh - file management helpers
#
# Release 0.5. Three subcommands:
#   files rename <pattern> [--prefix X] [--suffix Y] [--dry-run]
#   files sort [--path <dir>] [--dry-run]
#   files organize screenshots [--dest <dir>] [--dry-run]

emulate -L zsh
set -o errexit -o nounset -o pipefail

SCRIPT_DIR=${0:a:h}
REPO_DIR=${SCRIPT_DIR:h}
LIB_DIR="$REPO_DIR/lib"

source "$LIB_DIR/common.zsh"
source "$LIB_DIR/argparse.zsh"
source "$LIB_DIR/exitcodes.zsh"
source "$LIB_DIR/log.zsh"
source "$LIB_DIR/safety.zsh"

macadmin_parse_globals "$@" 2>/dev/null || true
if (( ${#MACADMIN_ARGS[@]} > 0 )); then
  set -- "${MACADMIN_ARGS[@]}"
else
  set --
fi
require_macos || exit 1

usage()
{
  cat <<'EOF'
files.zsh - file management helpers

Usage:
  files.zsh rename <pattern> [--prefix X] [--suffix Y] [--dry-run]
  files.zsh sort [--path <dir>] [--dry-run]
  files.zsh organize screenshots [--dest <dir>] [--dry-run]
  files.zsh help

Subcommands:
  rename <pattern>  Bulk rename files matching <pattern> in the current
                    directory. Add a --prefix and/or --suffix to each
                    match. --dry-run shows the plan without renaming.
                    Refuses to operate outside $HOME.

  sort [--path P]   Move files under <path> into subdirectories by type
                    (Documents/, Images/, Archives/, Audio/, Video/,
                    Other/). Path must be inside $HOME. --dry-run
                    shows the plan without moving.

  organize screenshots [--dest P]
                    Move Screenshot YYYY-MM-DD*.png (and .jpg) under
                    <path> (default: $HOME) into <dest>. Creates
                    <dest> if missing. --dry-run shows the plan.

Flags:
  --dry-run   Print planned actions without executing.
  --path P    Root directory (sort only).
  --prefix X  Prefix to prepend to each renamed file (rename only).
  --suffix Y  Suffix to insert before the extension (rename only).
  --dest P    Destination directory (organize only).

Safety:
  - All destructive operations honor MACADMIN_PROTECT and require --yes
    UNLESS --dry-run is supplied (dry-run is always safe).
  - All operations are scoped to $HOME; system paths are refused.
EOF
}

# --- rename subcommand ---

_files_rename()
{
  local pattern="" prefix="" suffix=""
  local dry_run=1   # default: dry-run; --no flag means user must opt in
  # Actually for rename: we want --dry-run to be the safe default but the
  # user must explicitly say they want to ACT. If --dry-run is NOT
  # supplied, treat as a real rename and require --yes. We add a hidden
  # --no-dry-run flag.
  local explicit_apply=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --prefix)
        (( $# >= 2 )) || { print -r -- "[ERROR] --prefix requires a value" >&2; exit ${EX_USAGE:-64}; }
        prefix="$2"; shift 2 ;;
      --suffix)
        (( $# >= 2 )) || { print -r -- "[ERROR] --suffix requires a value" >&2; exit ${EX_USAGE:-64}; }
        suffix="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --no-dry-run) dry_run=0; explicit_apply=1; shift ;;
      --json|--pretty|--quiet|--verbose|--yes|--protect) shift ;;
      --) shift; pattern="$1"; shift; break ;;
      -*) print -r -- "[ERROR] rename: unknown flag: $1" >&2; exit ${EX_USAGE:-64} ;;
      *)
        # First positional is the pattern.
        [[ -z "$pattern" ]] || { print -r -- "[ERROR] rename: only one pattern allowed" >&2; exit ${EX_USAGE:-64}; }
        pattern="$1"; shift ;;
    esac
  done

  if [[ -z "$pattern" ]]; then
    print -r -- "[ERROR] rename: pattern required" >&2
    exit ${EX_USAGE:-64}
  fi

  # Safety: refuse to operate outside $HOME (including system paths).
  local cwd="$PWD"
  if ! macadmin_safety_within "$cwd" "$HOME"; then
    print -r -- "[ERROR] rename: refusing to operate outside \$HOME (cwd=$cwd)" >&2
    exit ${EX_NOPERM:-77}
  fi

  # Apply gate if actually renaming.
  if (( ! dry_run )) && (( explicit_apply )); then
    if (( MACADMIN_PROTECT )); then
      print -r -- "[ERROR] rename: --protect blocks rename" >&2
      exit ${EX_NOPERM:-77}
    fi
    if (( ! MACADMIN_YES )); then
      print -r -- "[ERROR] rename: --no-dry-run requires --yes" >&2
      exit ${EX_NOPERM:-77}
    fi
  fi

  log_info "Rename plan for pattern '$pattern' (cwd=$cwd)"
  log_info "  prefix='$prefix' suffix='$suffix'"

  # Use zsh glob expansion; set NULL_GLOB so a non-matching pattern
  # produces no matches instead of a literal.
  setopt local_options NULL_GLOB
  local m
  for m in $~pattern; do
    [[ -e "$m" ]] || continue
    local dir="${m:h}"
    local base="${m:t}"
    local name="${base:r}"
    local ext="${base:e}"
    # If there's no extension, ext == base (zsh behavior). Handle that.
    [[ "$ext" == "$base" ]] && { dir="$dir/$base"; base=""; name=""; ext=""; }
    # Construct new name: <prefix><name><suffix>.<ext>
    local new_name="${prefix}${name}${suffix}"
    [[ -n "$ext" ]] && new_name="${new_name}.${ext}"
    local new_path="$dir/$new_name"

    print -r -- "rename: $m -> $new_path"

    if (( ! dry_run )); then
      mv -- "$m" "$new_path"
    fi
  done

  if (( dry_run )); then
    log_info "(dry-run; no changes made)"
  else
    log_info "Done."
  fi
}

# --- sort subcommand ---

# Allowlist of safe root paths for 'sort'. Subdirectories of $HOME that
# are explicitly intended as user drop-zones. macadmin refuses to
# sort anywhere else (system, network mounts, etc.) by default.
_files_sort_allowed_roots()
{
  print -r -- "$HOME/Downloads"
  print -r -- "$HOME/Desktop"
  print -r -- "$HOME/Documents"
}

# Map file extension -> subdirectory name.
_files_sort_bucket()
{
  local ext="${(L)1}"  # lowercase
  case "$ext" in
    pdf|doc|docx|txt|md|rtf|odt|pages|tex) print -r -- "Documents" ;;
    jpg|jpeg|png|gif|webp|svg|heic|tif|tiff|bmp) print -r -- "Images" ;;
    zip|tar|gz|bz2|xz|7z|rar|dmg|iso) print -r -- "Archives" ;;
    mp3|m4a|wav|flac|aac|ogg) print -r -- "Audio" ;;
    mp4|mov|avi|mkv|webm|m4v) print -r -- "Video" ;;
    *) print -r -- "Other" ;;
  esac
}

_files_sort()
{
  # IMPORTANT: do NOT name this variable 'path' — zsh reserves 'path' for
  # the $PATH array. `local path` shadows $PATH and breaks command lookup
  # (find, mv, mkdir, ...) for the rest of the function. Same warning
  # is in lib/io.zsh:138. We use 'target' instead.
  local target=""
  local dry_run=1
  local explicit_apply=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --path)
        (( $# >= 2 )) || { print -r -- "[ERROR] --path requires a value" >&2; exit ${EX_USAGE:-64}; }
        target="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --no-dry-run) dry_run=0; explicit_apply=1; shift ;;
      --json|--pretty|--quiet|--verbose|--yes|--protect) shift ;;
      --) shift; break ;;
      -*) print -r -- "[ERROR] sort: unknown flag: $1" >&2; exit ${EX_USAGE:-64} ;;
      *) shift ;;
    esac
  done

  target="${target:-$HOME/Downloads}"
  if [[ ! -d "$target" ]]; then
    print -r -- "[ERROR] sort: path not found: $target" >&2
    exit ${EX_NOINPUT:-66}
  fi
  target="${target:A}"

  # Allowlist check.
  local allowed_root=""
  local r
  for r in $(_files_sort_allowed_roots); do
    local abs="${r:A}"
    if [[ "$target" == "$abs" || "$target" == "$abs"/* ]]; then
      allowed_root="$abs"
      break
    fi
  done
  if [[ -z "$allowed_root" ]]; then
    print -r -- "[ERROR] sort: refusing to operate outside \$HOME/Downloads, Desktop, or Documents (got: $target)" >&2
    exit ${EX_NOPERM:-77}
  fi

  # Apply gate.
  if (( ! dry_run )) && (( explicit_apply )); then
    if (( MACADMIN_PROTECT )); then
      print -r -- "[ERROR] sort: --protect blocks sort" >&2
      exit ${EX_NOPERM:-77}
    fi
    if (( ! MACADMIN_YES )); then
      print -r -- "[ERROR] sort: --no-dry-run requires --yes" >&2
      exit ${EX_NOPERM:-77}
    fi
  fi

  log_info "Sort plan for $target"
  # Only act on top-level files (not subdirs); never re-organize a dir.
  # NB: pipe the loop through >/dev/stdout so `print` inside the while
  # body is actually visible (otherwise the pipe consumes it).
  # NOTE: use combined `local foo="$(...)"` to avoid the zsh scope-end
  # echo quirk inside the redirected while loop.
  local f
  find "$target" -maxdepth 1 -type f -print 2>/dev/null | while IFS= read -r f; do
    local name="${f:t}"
    local ext="${name:e}"
    local bucket="$(_files_sort_bucket "$ext")"
    local dest_dir="$target/$bucket"
    local dest_path="$dest_dir/$name"

    print -r -- "move: $f -> $dest_path"

    if (( ! dry_run )); then
      [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
      mv -- "$f" "$dest_path"
    fi
  done >/dev/stdout

  if (( dry_run )); then
    log_info "(dry-run; no changes made)"
  else
    log_info "Done."
  fi
}

# --- organize screenshots subcommand ---

_files_organize_screenshots()
{
  # IMPORTANT: do NOT name this variable 'path' (see _files_sort).
  local target="$HOME"
  local dest=""
  local dry_run=1
  local explicit_apply=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --dest)
        (( $# >= 2 )) || { print -r -- "[ERROR] --dest requires a value" >&2; exit ${EX_USAGE:-64}; }
        dest="$2"; shift 2 ;;
      --path)
        (( $# >= 2 )) || { print -r -- "[ERROR] --path requires a value" >&2; exit ${EX_USAGE:-64}; }
        target="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --no-dry-run) dry_run=0; explicit_apply=1; shift ;;
      --json|--pretty|--quiet|--verbose|--yes|--protect) shift ;;
      --) shift; break ;;
      -*) print -r -- "[ERROR] organize: unknown flag: $1" >&2; exit ${EX_USAGE:-64} ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "$target" ]]; then
    print -r -- "[ERROR] organize: path not found: $target" >&2
    exit ${EX_NOINPUT:-66}
  fi
  target="${target:A}"

  if [[ -z "$dest" ]]; then
    dest="$HOME/Pictures/Screenshots"
  fi
  dest="${dest:A}"

  # Allowlist: dest must be inside $HOME (otherwise it's a system path
  # that we should not write to).
  if ! macadmin_safety_within "$dest" "$HOME"; then
    print -r -- "[ERROR] organize: --dest must be inside \$HOME (got: $dest)" >&2
    exit ${EX_NOPERM:-77}
  fi
  if ! macadmin_safety_within "$target" "$HOME"; then
    print -r -- "[ERROR] organize: --path must be inside \$HOME (got: $target)" >&2
    exit ${EX_NOPERM:-77}
  fi

  if (( ! dry_run )) && (( explicit_apply )); then
    if (( MACADMIN_PROTECT )); then
      print -r -- "[ERROR] organize: --protect blocks organize" >&2
      exit ${EX_NOPERM:-77}
    fi
    if (( ! MACADMIN_YES )); then
      print -r -- "[ERROR] organize: --no-dry-run requires --yes" >&2
      exit ${EX_NOPERM:-77}
    fi
  fi

  log_info "Organize-screenshots plan: $target -> $dest"

  # Match "Screenshot ..." and "Screen Shot ..." with .png/.jpg/.jpeg
  # extension (case-insensitive). Use zsh glob with (#i) — more reliable
  # than find -regex with variable substitution. `**/*` covers current
  # dir + recursive subdirs.
  setopt local_options NULL_GLOB EXTENDED_GLOB
  local matches
  matches=( $target/**/(#i)(Screenshot|Screen\ Shot)*.(#i)(png|jpg|jpeg) )

  if (( ${#matches[@]} == 0 )); then
    log_info "No screenshots found."
    return 0
  fi

  local f
  for f in "${matches[@]}"; do
    [[ -f "$f" ]] || continue
    local name="${f:t}"
    local dest_path="$dest/$name"
    print -r -- "move: $f -> $dest_path"
    if (( ! dry_run )); then
      [[ -d "$dest" ]] || mkdir -p "$dest"
      mv -- "$f" "$dest_path"
    fi
  done

  if (( dry_run )); then
    log_info "(dry-run; no changes made)"
  else
    log_info "Done."
  fi
}

# --- dispatcher ---

subcmd=${1:-}
case "$subcmd" in
  ""|-h|--help|help) usage; exit 0 ;;
  rename)
    shift
    _files_rename "$@"
    ;;
  sort)
    shift
    _files_sort "$@"
    ;;
  organize)
    shift
    case "${1:-}" in
      screenshots) shift; _files_organize_screenshots "$@" ;;
      -h|--help|help|"") usage; exit 0 ;;
      *) print -r -- "[ERROR] files organize: unknown sub: $1" >&2; exit ${EX_USAGE:-64} ;;
    esac
    ;;
  *)
    print -r -- "[ERROR] files: unknown subcommand: ${subcmd:-<none>}" >&2
    usage >&2
    exit ${EX_USAGE:-64}
    ;;
esac

exit ${EX_OK:-0}
