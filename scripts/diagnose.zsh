#!/usr/bin/env zsh
# shellcheck shell=bash disable=SC2154
# diagnose.zsh - diagnostic helpers for macOS
#
# Release 0.4 multi-subcommand dispatcher. Replaces the mac-scripts
# mac-freeze-diagnose + mac-cleanup-sh utilities with a first-class
# macadmin command. Each subcommand is independent and read-only by
# default; mutating operations (real sample/spindump capture in
# 'freeze') require --yes and respect MACADMIN_PROTECT.
#
# Subcommands:
#   summary [--json|--pretty]   Snapshot of system + disk + memory + uptime.
#   cleanup [--older-than N] [--larger-than S] [--path P] [--json|--pretty]
#                               Read-only scanner: finds files matching
#                               age/size criteria. Never deletes anything.
#   freeze --dry-run             Print the planned diagnostic capture
#                               actions without executing. Full freeze
#                               (sample/spindump/log show + tarball) is
#                               deferred — requires sudo + extensive
#                               mocking to test safely in CI.

emulate -L zsh
set -o errexit -o nounset -o pipefail

SCRIPT_DIR=${0:a:h}
REPO_DIR=${SCRIPT_DIR:h}
LIB_DIR="$REPO_DIR/lib"

source "$LIB_DIR/common.zsh"
source "$LIB_DIR/argparse.zsh"
source "$LIB_DIR/exitcodes.zsh"
source "$LIB_DIR/log.zsh"

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
diagnose.zsh - diagnostic helpers for macOS

Usage:
  diagnose.zsh summary [--json|--pretty]
  diagnose.zsh cleanup [--path <root>] [--older-than <days>]
                       [--larger-than <size>] [--json|--pretty]
  diagnose.zsh freeze --dry-run
  diagnose.zsh help

Subcommands:
  summary    Single-shot JSON snapshot of system + disk + memory + uptime
             + network interfaces. Designed for automation + dashboards.

  cleanup    Read-only file scanner: lists files under --path (default:
             $HOME) matching the supplied age/size filters. Never deletes
             anything. Output is line-delimited JSON (one object per file)
             or pretty-printed array. Equivalent to the mac-scripts
             `mac-cleanup-sh --scan` mode, lifted into macadmin.

  freeze     Print the planned diagnostic capture actions (sample,
             spindump, log show, top, ps, tarball) without running them.
             Full execution requires sudo + external tools; deferred to a
             follow-up release.

Flags:
  --dry-run   Print planned actions without executing (used by 'freeze').
  --json      JSON output (compact, one object per line for scans).
  --pretty    Pretty-printed JSON (single object or array).
  -h, --help  Show this help.

Notes:
  - All subcommands are read-only by design.
  - 'freeze' currently only supports --dry-run; real capture is future work.
EOF
}

# --- shared field helpers (lifted from system_info.zsh for cohesion) ---

_sw_val()
{
  local key="$1"
  sw_vers 2>/dev/null | awk -v k="$key" 'BEGIN{FS=":[ \t]*"} $1==k {print $2; exit}'
}

_mem_gb()
{
  local bytes
  bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  if [[ "$bytes" != 0 ]]; then
    awk -v b="$bytes" 'BEGIN{printf "%.1f", b/1024/1024/1024}'
  else
    echo 0
  fi
}

_hw_model_and_chip()
{
  local sp
  sp=$(system_profiler SPHardwareDataType 2>/dev/null || true)
  # Emit ONE line "model<TAB>chip" so a single `read` can consume both.
  # macOS BWK awk does NOT honor multi-char -F separators (treats -F': '
  # as -F':'); use a single-char FS and trim leading whitespace from $2.
  print -r -- "$sp" | awk -F':' '
    /Model Identifier/  { gsub(/^[[:space:]]+/, "", $2); m=$2 }
    /Chip:/             { gsub(/^[[:space:]]+/, "", $2); c=$2 }
    /Processor Name/    { if (c == "") { gsub(/^[[:space:]]+/, "", $2); c=$2 } }
    END                 { print m "\t" c }
  '
}

_disk_gb()
{
  # _disk_gb <total|free> for primary volume '/'
  local field="$1" line blocks used avail
  line=$(df -k / 2>/dev/null | awk 'NR==2')
  blocks=$(print -r -- "$line" | awk '{print $2}')
  avail=$(print -r -- "$line" | awk '{print $4}')
  case "$field" in
    total) awk -v k="$blocks" 'BEGIN{printf "%.1f", k/1024/1024}' ;;
    free)  awk -v k="$avail"  'BEGIN{printf "%.1f", k/1024/1024}' ;;
    *) echo 0 ;;
  esac
}

_json_escape()
{
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  print -r -- "$s"
}

_interfaces_json()
{
  # Deterministic object of interfaces with IPs: {"en0":"192.168.0.2",...}
  local devs first=1 out="{"
  devs=($(networksetup -listallhardwareports 2>/dev/null | awk '/Device:/{print $2}' | sort))
  local d ip
  for d in $devs; do
    ip=$(ipconfig getifaddr "$d" 2>/dev/null || true)
    [[ -z "$ip" ]] && continue
    local key val
    key=$(_json_escape "$d")
    val=$(_json_escape "$ip")
    if ((first)); then first=0; else out+=","; fi
    out+="\"$key\":\"$val\""
  done
  out+="}"
  print -r -- "$out"
}

_uptime_seconds()
{
  local sec now
  # sysctl -n kern.boottime on macOS prints e.g.
  #   "{ sec = 1700000000, usec = 0 }"
  # Split on whitespace + comma; the number after the "sec" token is the
  # boot epoch. Original system_info.zsh used $(i+2) which landed on the
  # "usec" field — fix is $(i+1).
  sec=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[ =,]+' '
    { for (i=1;i<=NF;i++) if ($i == "sec") { print $(i+1); exit } }
  ')
  : "${sec:=0}"
  now=$(date +%s)
  if [[ -n "$sec" && "$sec" != 0 ]]; then
    echo $((now - sec))
  else
    echo 0
  fi
}

_iso_ts()
{
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# --- summary subcommand ---

_diag_summary()
{
  local pretty=0
  for a in "$@"; do [[ "$a" == "--pretty" ]] && pretty=1; done

  local pv build model chip mem_gb disk_total disk_free ifaces uptime ts
  pv=$(_sw_val ProductVersion)
  build=$(_sw_val BuildVersion)
  {
    IFS=$'\t' read -r model chip
  } <<<"$(_hw_model_and_chip)"
  mem_gb=$(_mem_gb)
  disk_total=$(_disk_gb total)
  disk_free=$(_disk_gb free)
  ifaces=$(_interfaces_json)
  uptime=$(_uptime_seconds)
  ts=$(_iso_ts)

  if ((MACADMIN_JSON)) || ((pretty)); then
    # The `interfaces` field is itself a JSON object. Pass it raw (key
    # suffix `:` in macadmin_json_obj_kv tells the helper NOT to quote)
    # so the nested braces and quotes don't get double-escaped.
    if ((pretty)); then
      printf '{\n'
      printf '  "product_version": "%s",\n' "$(_json_escape "$pv")"
      printf '  "build": "%s",\n' "$(_json_escape "$build")"
      printf '  "model_id": "%s",\n' "$(_json_escape "${model:-}")"
      printf '  "chip": "%s",\n' "$(_json_escape "${chip:-}")"
      printf '  "memory_gb": %s,\n' "${mem_gb:-0}"
      printf '  "primary_volume": "/",\n'
      printf '  "disk_total_gb": %s,\n' "${disk_total:-0}"
      printf '  "disk_free_gb": %s,\n' "${disk_free:-0}"
      printf '  "interfaces": %s,\n' "$ifaces"
      printf '  "uptime_seconds": %s,\n' "${uptime:-0}"
      printf '  "ts": "%s"\n' "$(_json_escape "$ts")"
      printf '}\n'
    else
      printf '{'
      printf '"product_version":"%s"' "$(_json_escape "$pv")"
      printf ',"build":"%s"' "$(_json_escape "$build")"
      printf ',"model_id":"%s"' "$(_json_escape "${model:-}")"
      printf ',"chip":"%s"' "$(_json_escape "${chip:-}")"
      printf ',"memory_gb":%s' "${mem_gb:-0}"
      printf ',"primary_volume":"/"'
      printf ',"disk_total_gb":%s' "${disk_total:-0}"
      printf ',"disk_free_gb":%s' "${disk_free:-0}"
      printf ',"interfaces":%s' "$ifaces"
      printf ',"uptime_seconds":%s' "${uptime:-0}"
      printf ',"ts":"%s"' "$(_json_escape "$ts")"
      printf '}\n'
    fi
  else
    print -r -- "product_version: $pv"
    print -r -- "build: $build"
    print -r -- "model_id: ${model:-}"
    print -r -- "chip: ${chip:-}"
    print -r -- "memory_gb: $mem_gb"
    print -r -- "primary_volume: /"
    print -r -- "disk_total_gb: $disk_total"
    print -r -- "disk_free_gb: $disk_free"
    print -r -- "interfaces: $ifaces"
    print -r -- "uptime_seconds: $uptime"
    print -r -- "ts: $ts"
  fi
}

# --- cleanup subcommand ---

# Parse a human size string like "1M", "500K", "2G" into bytes.
# Returns 0 and prints bytes, or returns 1 if unparseable.
_parse_size_to_bytes()
{
  local raw="$1"
  local num unit mult
  num=$(print -r -- "$raw" | awk 'BEGIN{IGNORECASE=1} {gsub(/[kKmMgGtT]/,""); print}')
  unit=$(print -r -- "$raw" | tr -d '[:digit:]. ')
  case "${unit:l}" in
    k|"") mult=1024 ;;
    m) mult=$((1024*1024)) ;;
    g) mult=$((1024*1024*1024)) ;;
    t) mult=$((1024*1024*1024*1024)) ;;
    *) return 1 ;;
  esac
  awk -v n="$num" -v m="$mult" 'BEGIN{printf "%d", n*m}'
}

# Build the find arg list given the parsed filters. Echoes nothing; sets
# the _FIND_ARGS array in the caller's scope (zsh dynamic scoping).
_diag_cleanup_find_args()
{
  typeset -ga _FIND_ARGS=()
  local min_bytes="$1" atime_days="$2" root="$3"

  _FIND_ARGS=("$root" -type f)

  if (( min_bytes > 0 )); then
    # Use bytes-suffix (c) so we compare in bytes, matching the unit
    # we parsed from the --larger-than flag.
    _FIND_ARGS+=(-size "+${min_bytes}c")
  fi

  if (( atime_days > 0 )); then
    _FIND_ARGS+=(-atime "+${atime_days}")
  fi
}

# Format a Unix timestamp as ISO-8601 UTC.
_iso_from_atime()
{
  local atime="$1"
  if [[ -z "$atime" || "$atime" == "0" ]]; then
    print -r -- ""
    return 0
  fi
  date -u -r "$atime" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || print -r -- ""
}

_diag_cleanup()
{
  local root="$HOME"
  local older_than_days=0
  local larger_than=""
  local pretty=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --path)
        (( $# >= 2 )) || { print -r -- "[ERROR] --path requires a value" >&2; exit ${EX_USAGE:-64}; }
        root="$2"; shift 2 ;;
      --older-than)
        (( $# >= 2 )) || { print -r -- "[ERROR] --older-than requires a value" >&2; exit ${EX_USAGE:-64}; }
        older_than_days="$2"; shift 2 ;;
      --larger-than)
        (( $# >= 2 )) || { print -r -- "[ERROR] --larger-than requires a value" >&2; exit ${EX_USAGE:-64}; }
        larger_than="$2"; shift 2 ;;
      --pretty) pretty=1; shift ;;
      --json|--quiet|--verbose|--dry-run|--yes|--protect) shift ;;
      --) shift; break ;;
      -*) print -r -- "[ERROR] cleanup: unknown flag: $1" >&2; exit ${EX_USAGE:-64} ;;
      *)  shift ;;
    esac
  done

  if [[ ! -d "$root" ]]; then
    print -r -- "[ERROR] cleanup: path not found: $root" >&2
    exit ${EX_NOINPUT:-66}
  fi

  # Resolve to absolute path (also normalizes ~/).
  root="${root:A}"

  # Validate --older-than.
  if ! [[ "$older_than_days" =~ ^[0-9]+$ ]]; then
    print -r -- "[ERROR] cleanup: --older-than must be a non-negative integer" >&2
    exit ${EX_USAGE:-64}
  fi

  # Parse --larger-than (allow empty -> 0).
  local min_bytes=0
  if [[ -n "$larger_than" ]]; then
    min_bytes=$(_parse_size_to_bytes "$larger_than") || {
      print -r -- "[ERROR] cleanup: invalid --larger-than: $larger_than (expected NNN[N]\?[K|M|G|T])" >&2
      exit ${EX_USAGE:-64}
    }
  fi

  _diag_cleanup_find_args "$min_bytes" "$older_than_days" "$root"

  # Run find. Capture paths; per-file stat goes through a helper to keep
  # the loop body small and free of the zsh scope-end echo quirk.
  local paths
  paths=$(find "${_FIND_ARGS[@]}" 2>/dev/null)

  if ((MACADMIN_JSON)) || ((pretty)); then
    local first=1
    if ((pretty)); then printf '[\n'; fi
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      # Each iteration extracts via helper functions to avoid `local x; x=$(...)`
      # in loop scope (zsh quirk). The helpers echo the formatted fields.
      _emit_cleanup_object "$p" "$((pretty))" "$first"
      first=0
    done <<<"$paths"
    if ((pretty)); then printf '\n]\n'; fi
  else
    print -r -- "Scanning $root (older_than=${older_than_days}d larger_than=${larger_than:-0B})..."
    if [[ -z "$paths" ]]; then
      print -r -- "No files found."
    else
      print -r -- "PATH | SIZE | ATIME"
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        # Combined declare+assign to avoid zsh scope-end echo quirk.
        local line="$(_format_cleanup_line "$p")"
        print -r -- "$line"
      done <<<"$paths"
    fi
  fi
}

# Emit one JSON object for a file path. Echoes to stdout. Caller controls
# the leading-comma logic for pretty arrays.
#
# Usage: _emit_cleanup_object <path> <is_pretty:0|1> <is_first:0|1>
_emit_cleanup_object()
{
  local p="$1" is_pretty="$2" is_first="$3"
  local sz_b atime atime_iso
  sz_b="$(stat -f %z "$p" 2>/dev/null || echo 0)"
  atime="$(stat -f %a "$p" 2>/dev/null || echo 0)"
  atime_iso="$(_iso_from_atime "$atime")"
  local kv=(path="$p" size_bytes="$sz_b" atime_iso="$atime_iso")
  if (( is_pretty )); then
    (( is_first )) || printf ',\n'
    printf '  '
    macadmin_json_pretty_obj "$kv[@]"
  else
    macadmin_json_obj "$kv[@]"
    printf '\n'
  fi
}

# Format a file path as the human-readable "PATH | SIZE | ATIME" row.
_format_cleanup_line()
{
  local p="$1"
  # All assignments combined with `local` on one line to avoid the zsh
  # scope-end echo quirk inside the calling while-read loop.
  local sz_b="$(stat -f %z "$p" 2>/dev/null || echo 0)"
  local atime="$(stat -f %a "$p" 2>/dev/null || echo 0)"
  local atime_iso="$(_iso_from_atime "$atime")"
  local hsz
  if (( sz_b >= 1073741824 )); then
    hsz="$((sz_b / 1073741824 ))G"
  elif (( sz_b >= 1048576 )); then
    hsz="$((sz_b / 1048576 ))M"
  elif (( sz_b >= 1024 )); then
    hsz="$((sz_b / 1024 ))K"
  else
    hsz="${sz_b}B"
  fi
  print -r -- "$p | ${hsz} | $atime_iso"
}

# --- freeze subcommand (dry-run only in this release) ---

_diag_freeze()
{
  local do_run=0
  local outdir=""
  for a in "$@"; do
    case "$a" in
      --dry-run) do_run=0 ;;
      --output) shift; outdir="${1:-}" ;;
      -h|--help) usage; exit 0 ;;
    esac
  done

  # Real freeze requires sudo + sample/spindump/log show. That whole
  # workflow is deferred to a follow-up. For 0.4.0 we only ship the
  # planning step so callers (and CI) can verify the action list.
  local stamp outdir_default
  stamp=$(date +%Y%m%d-%H%M%S)
  outdir_default="$HOME/Desktop/mac-freeze-$stamp"
  : "${outdir:=$outdir_default}"

  log_info "freeze: dry-run — printing planned actions (no execution)"
  print -r -- "Planned output directory: $outdir"
  print -r -- "Steps:"
  print -r -- "  1. mkdir -p $outdir"
  print -r -- "  2. system_profiler SPHardwareDataType | head -n 200 > $outdir/00_system.txt"
  print -r -- "  3. sw_vers > $outdir/00_system.txt (append)"
  print -r -- "  4. uptime > $outdir/00_system.txt (append)"
  print -r -- "  5. sysctl -n machdep.cpu.brand_string > $outdir/00_system.txt (append)"
  print -r -- "  6. top -l 1 -n 0 -stats pid,command,cpu,mem,threads,ports,time > $outdir/10_top_once.txt"
  print -r -- "  7. top -l 5 -n 0 -stats pid,command,cpu,mem,threads,ports,time > $outdir/11_top_5x.txt"
  print -r -- "  8. memory_pressure -l 5 > $outdir/20_memory.txt"
  print -r -- "  9. vm_stat > $outdir/20_memory.txt (append)"
  print -r -- " 10. iostat -w 1 -c 10 > $outdir/30_iostat.txt"
  print -r -- " 11. sudo powermetrics --samplers smc,thermal,interrupt -n 15 -i 1000 > $outdir/40_powermetrics.txt  # needs sudo"
  print -r -- " 12. log show --last 15m --predicate 'process == \"WindowServer\"' > $outdir/50_logs.txt  # WindowServer"
  print -r -- " 13. log show --last 15m --predicate 'process == \"kernel\"' >> $outdir/50_logs.txt"
  print -r -- " 14. log show --last 15m --predicate 'eventMessage CONTAINS[c] \"watchdog\" OR ...hang' >> $outdir/50_logs.txt"
  print -r -- " 15. find \$HOME/Library/Logs/DiagnosticReports -type f -name '*.crash' -mtime -1 -exec cp {} $outdir/60_crashes/ \;"
  print -r -- " 16. sudo spindump -i 10 -file $outdir/70_spindump.system.spin  # needs sudo"
  print -r -- " 17. osascript -e 'tell application \"System Events\" to get frontmost process' > $outdir/80_frontmost_app.txt"
  print -r -- " 18. ps -axo pid,ppid,ruid,stat,pri,nice,psr,%cpu,%mem,threads,etime,command > $outdir/90_ps.txt"
  print -r -- ""
  print -r -- "Real execution is NOT yet implemented in 0.4.0 — deferred to a follow-up release."
}

# --- dispatcher ---

subcmd=${1:-}
case "$subcmd" in
  ""|-h|--help|help) usage; exit 0 ;;
  summary) shift; _diag_summary "$@" ;;
  cleanup) shift; _diag_cleanup "$@" ;;
  freeze) shift; _diag_freeze "$@" ;;
  *)
    print -r -- "[ERROR] diagnose: unknown subcommand: ${subcmd:-<none>}" >&2
    usage >&2
    exit ${EX_USAGE:-64}
    ;;
esac

exit ${EX_OK:-0}
