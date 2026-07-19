#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
# archive.zsh - archive creation + recompression
#
# Release 0.6. Two subcommands:
#   archive create <sources...> [--output <path>] [--format 7z|zip]
#                          [--delete-sources] [--yes] [--protect]
#                          [--dry-run] [--json|--pretty]
#   archive recompress <input> [--output <path>] [--yes]
#
# Notes:
#   - 'zip' is built into macOS (/usr/bin/zip).
#   - '7z' is NOT built in; if --format 7z is requested and '7z' is not on
#     PATH, archive exits with EX_UNAVAILABLE (69) and a clear message.
#     Install via `brew install p7zip`.
#   - All destructive operations honor MACADMIN_PROTECT (blocks
#     outright) and require --yes when not --dry-run.

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
archive.zsh - archive creation + recompression

Usage:
  archive.zsh create <sources...> [--output <path>] [--format 7z|zip]
                          [--delete-sources] [--yes] [--protect]
                          [--dry-run] [--json|--pretty]
  archive.zsh recompress <input> [--output <path>] [--yes]
  archive.zsh help

Subcommands:
  create       Bundle <sources...> into a zip or 7z archive at <output>.
               Defaults to ./macadmin-archive-<timestamp>.<ext> in cwd.
               With --delete-sources, removes the originals after the
               archive is created. Requires --yes. Blocked by --protect.

  recompress   Recompress an existing zip archive into a new 7z archive
               (smaller). Defaults to <input>.7z next to <input>.

Flags:
  --output <path>      Output archive path. Default is timestamped.
  --format 7z|zip      Archive format (default: zip).
  --delete-sources     After successful archive, remove originals. Requires --yes.
  --dry-run            Print planned actions without executing.
  --json|--pretty      JSON output (compact or pretty).
  --yes                Confirm destructive actions.
  --protect            Refuse destructive actions even with --yes.

Examples:
  archive.zsh create ~/Documents/report.pdf ~/Documents/notes.txt
  archive.zsh create mydir/ --output backup.zip
  archive.zsh create logs/*.log --format 7z --output logs.7z --delete-sources --yes

Notes:
  - 'zip' is built into macOS.
  - '7z' must be installed separately (brew install p7zip).
EOF
}

# Resolve a format string to the executable name + extension.
# Echoes "<cmd>|<ext>". Returns EX_UNAVAILABLE if the command isn't found.
_archive_resolve_format()
{
  local fmt="$1"
  case "$fmt" in
    zip)
      if command -v zip >/dev/null 2>&1; then
        print -r -- "zip|zip"
        return 0
      fi
      print -r -- "[ERROR] archive: 'zip' not found in PATH" >&2
      return ${EX_UNAVAILABLE:-69}
      ;;
    7z)
      if command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1; then
        print -r -- "7z|7z"
        return 0
      fi
      print -r -- "[ERROR] archive: '7z' not found in PATH (install via 'brew install p7zip')" >&2
      return ${EX_UNAVAILABLE:-69}
      ;;
    *)
      print -r -- "[ERROR] archive: unsupported format: $fmt (use zip or 7z)" >&2
      return ${EX_USAGE:-64}
      ;;
  esac
}

_archive_resolve_7z_cmd()
{
  if command -v 7z >/dev/null 2>&1; then
    print -r -- "7z"
  elif command -v 7za >/dev/null 2>&1; then
    print -r -- "7za"
  else
    return 1
  fi
}

# --- create subcommand ---

_archive_create()
{
  local output=""
  local format="zip"
  local delete_sources=0
  local dry_run=1   # default: dry-run; --no-dry-run is explicit-apply
  local pretty=0
  local explicit_apply=0
  local -a sources=()

  # Scan ALL args — flags may appear before OR after positional sources.
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --output)
        (( $# >= 2 )) || { print -r -- "[ERROR] --output requires a value" >&2; exit ${EX_USAGE:-64}; }
        output="$2"; shift 2 ;;
      --format)
        (( $# >= 2 )) || { print -r -- "[ERROR] --format requires a value" >&2; exit ${EX_USAGE:-64}; }
        format="$2"; shift 2 ;;
      --delete-sources)
        # --delete-sources signals destructive intent; the safety gate
        # below will refuse it without --yes even in --dry-run mode.
        delete_sources=1
        shift
        ;;
      --dry-run) dry_run=1; shift ;;
      --no-dry-run) dry_run=0; explicit_apply=1; shift ;;
      --pretty) pretty=1; shift ;;
      --json|--quiet|--verbose|--yes|--protect) shift ;;
      -*) print -r -- "[ERROR] archive: unknown flag: $1" >&2; exit ${EX_USAGE:-64} ;;
      *) sources+=("$1"); shift ;;
    esac
  done

  if (( ${#sources[@]} == 0 )); then
    print -r -- "[ERROR] archive create: at least one source required" >&2
    exit ${EX_USAGE:-64}
  fi

  # Validate every source exists. Do this even on --dry-run (planning).
  local s
  for s in "${sources[@]}"; do
    [[ -e "$s" ]] || { print -r -- "[ERROR] archive: source not found: $s" >&2; exit ${EX_NOINPUT:-66}; }
  done

  # Default output: <cwd>/macadmin-archive-<ts>.<ext>
  local ts cmd ext resolved
  ts=$(date +%Y%m%d-%H%M%S)
  local resolved_info
  resolved_info="$(_archive_resolve_format "$format")" || exit $?
  cmd="${resolved_info%|*}"
  ext="${resolved_info#*|}"

  if [[ -z "$output" ]]; then
    output="$PWD/macadmin-archive-$ts.$ext"
  fi
  output="${output:A}"

  # Safety gate: destructive ops require --yes. Two paths trigger:
  #   (a) --delete-sources — signals intent to delete the originals
  #       (destructive even in --dry-run mode).
  #   (b) --no-dry-run with explicit_apply — actually executes.
  if (( delete_sources )) || (( ! dry_run && explicit_apply )); then
    if (( MACADMIN_PROTECT )); then
      print -r -- "[ERROR] archive: --protect blocks destructive operation" >&2
      exit ${EX_NOPERM:-77}
    fi
    if (( ! MACADMIN_YES )); then
      local reason
      if (( delete_sources )) && (( ! ( ! dry_run && explicit_apply ) )); then
        reason="--delete-sources requires --yes (or use --dry-run without --delete-sources)"
      else
        reason="--no-dry-run requires --yes (or use --dry-run)"
      fi
      print -r -- "[ERROR] archive: $reason" >&2
      exit ${EX_NOPERM:-77}
    fi
  fi

  # Planning output (human + JSON both emit the same plan).
  log_info "archive plan:"
  log_info "  format: $format"
  log_info "  output: $output"
  log_info "  delete_sources: $delete_sources"
  for s in "${sources[@]}"; do
    log_info "  source: $s"
  done

  if ((MACADMIN_JSON)) || ((pretty)); then
    local kv first=1
    if ((pretty)); then printf '{\n'; fi
    kv=(event="archive_create" format="$format" output="$output" delete_sources="$delete_sources" dry_run="$dry_run")
    if ((pretty)); then
      printf '  '
      macadmin_json_pretty_obj "$kv[@]"
    else
      macadmin_json_obj "$kv[@]"
      printf '\n'
    fi
    for s in "${sources[@]}"; do
      local skv
      skv=(source="$s")
      if ((pretty)); then
        printf ',\n  '
        macadmin_json_pretty_obj "$skv[@]"
      else
        macadmin_json_obj "$skv[@]"
        printf '\n'
      fi
    done
    if ((pretty)); then printf '\n}\n'; fi
  fi

  if (( dry_run )); then
    log_info "(dry-run; no archive created)"
    return 0
  fi

  # Actually create the archive.
  local exit_code=0
  case "$format" in
    zip)
      # `zip -r <output> <sources...>` archives recursively.
      # Use a temp working dir to avoid including the output in itself.
      local workdir
      workdir=$(mktemp -d -t macadmin_archive.XXXXXX)
      # Copy sources into workdir preserving basenames (zip stores
      # relative paths; putting everything at top-level is simpler).
      local base
      for s in "${sources[@]}"; do
        base="${s##*/}"
        if [[ -d "$s" ]]; then
          cp -R "$s" "$workdir/$base"
        else
          cp "$s" "$workdir/$base"
        fi
      done
      ( cd "$workdir" && zip -r "$output" . ) || exit_code=$?
      rm -rf "$workdir"
      ;;
    7z)
      local sz
      sz="$(_archive_resolve_7z_cmd)" || {
        print -r -- "[ERROR] archive: '7z' not found in PATH" >&2
        exit ${EX_UNAVAILABLE:-69}
      }
      # `7z a <output> <sources...>` appends to archive.
      "$sz" a "$output" "${sources[@]}" || exit_code=$?
      ;;
  esac

  if (( exit_code != 0 )); then
    print -r -- "[ERROR] archive: $format command failed (exit=$exit_code)" >&2
    exit $exit_code
  fi

  # Delete sources only after the archive was created successfully AND
  # the user explicitly requested it.
  if (( delete_sources )); then
    log_info "Deleting original sources..."
    local s
    for s in "${sources[@]}"; do
      rm -rf -- "$s" && log_info "deleted: $s"
    done
  fi

  log_info "Done: $output"
}

# --- recompress subcommand ---

_archive_recompress()
{
  local output=""
  local dry_run=1
  local explicit_apply=0
  local input=""

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --output)
        (( $# >= 2 )) || { print -r -- "[ERROR] --output requires a value" >&2; exit ${EX_USAGE:-64}; }
        output="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --no-dry-run) dry_run=0; explicit_apply=1; shift ;;
      --yes) shift ;;
      --pretty|--json|--quiet|--verbose|--protect) shift ;;
      -*) print -r -- "[ERROR] archive: unknown flag: $1" >&2; exit ${EX_USAGE:-64} ;;
      *) input="$1"; shift ;;
    esac
  done

  if [[ -z "$input" ]]; then
    print -r -- "[ERROR] archive recompress: input archive required" >&2
    exit ${EX_USAGE:-64}
  fi
  [[ -f "$input" ]] || { print -r -- "[ERROR] archive: input not found: $input" >&2; exit ${EX_NOINPUT:-66}; }

  if [[ -z "$output" ]]; then
    output="${input%.zip}.7z"
  fi
  output="${output:A}"

  local sz
  sz="$(_archive_resolve_7z_cmd)" || {
    print -r -- "[ERROR] archive: '7z' not found in PATH (install via 'brew install p7zip')" >&2
    exit ${EX_UNAVAILABLE:-69}
  }

  if (( MACADMIN_PROTECT )) && (( ! dry_run )); then
    print -r -- "[ERROR] archive recompress: --protect blocks" >&2
    exit ${EX_NOPERM:-77}
  fi
  if (( ! dry_run )) && (( ! MACADMIN_YES )); then
    print -r -- "[ERROR] archive recompress: requires --yes" >&2
    exit ${EX_NOPERM:-77}
  fi

  log_info "recompress plan:"
  log_info "  input:  $input"
  log_info "  output: $output"

  if (( dry_run )); then
    log_info "(dry-run; not compressing)"
    return 0
  fi

  "$sz" a "$output" "$input" || {
    local rc=$?
    print -r -- "[ERROR] archive recompress: 7z failed (exit=$rc)" >&2
    exit $rc
  }
  log_info "Done: $output"
}

# --- dispatcher ---

subcmd=${1:-}
case "$subcmd" in
  ""|-h|--help|help) usage; exit 0 ;;
  create) shift; _archive_create "$@" ;;
  recompress) shift; _archive_recompress "$@" ;;
  *)
    print -r -- "[ERROR] archive: unknown subcommand: ${subcmd:-<none>}" >&2
    usage >&2
    exit ${EX_USAGE:-64}
    ;;
esac

exit ${EX_OK:-0}
