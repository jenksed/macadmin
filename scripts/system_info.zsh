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
system_info.zsh - print stable system key/value pairs or JSON

Usage:
  system_info.zsh [--json]

Outputs:
  - Human-readable: key: value lines
  - JSON (--json): single JSON object with deterministic key order

Examples:
  system_info.zsh
  system_info.zsh --json | jq -r .product_version
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

# Minimal JSON escaper (strings)
_json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  print -r -- "$s"
}

# Read fields with safe fallbacks
_sw_val() {
  local key="$1"
  sw_vers 2>/dev/null | awk -v k="$key" 'BEGIN{FS=":[ \t]*"} $1==k {print $2; exit}'
}

_get_mem_gb() {
  local bytes
  bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  if [[ "$bytes" != 0 ]]; then
    awk -v b="$bytes" 'BEGIN{printf "%.1f", b/1024/1024/1024}'
  else
    echo 0
  fi
}

_get_hw() {
  # Extract model identifier and chip if available
  local sp
  sp=$(system_profiler SPHardwareDataType 2>/dev/null || true)
  print -r -- "$sp" | awk -F': ' '/Model Identifier/{m=$2} /Chip:/{c=$2} /Processor Name:/{c=$2} END{print m "\n" c}'
}

_primary_volume() {
  echo "/"
}

_disk_gb() {
  # _disk_gb free|total for primary volume '/'
  local field="$1" line
  line=$(df -k / 2>/dev/null | awk 'NR==2')
  local blocks used avail
  blocks=$(print -r -- "$line" | awk '{print $2}')
  used=$(print -r -- "$line" | awk '{print $3}')
  avail=$(print -r -- "$line" | awk '{print $4}')
  local total=$(( blocks ))
  local free=$(( avail ))
  local val_k=0
  case "$field" in
    total) val_k=$total ;;
    free)  val_k=$free ;;
  esac
  awk -v k="$val_k" 'BEGIN{printf "%.1f", k/1024/1024}'
}

_interfaces_json_fragment() {
  # Deterministic object of interfaces with IPs: {"en0":"192.168.0.2",...}
  local devs
  devs=($(networksetup -listallhardwareports 2>/dev/null | awk '/Device:/{print $2}' | sort))
  local first=1 out="{"
  local d ip
  for d in $devs; do
    ip=$(ipconfig getifaddr "$d" 2>/dev/null || true)
    [[ -z "$ip" ]] && continue
    local key val
    key=$(_json_escape "$d"); val=$(_json_escape "$ip")
    if (( first )); then first=0; else out+=","; fi
    out+="\"$key\":\"$val\""
  done
  out+="}"
  print -r -- "$out"
}

_uptime_seconds() {
  local sec now
  sec=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[ =,]' '{for(i=1;i<=NF;i++)if($i=="sec"){print $(i+2);exit}}' || echo 0)
  now=$(date +%s)
  if [[ -n "$sec" && "$sec" != 0 ]]; then
    echo $(( now - sec ))
  else
    echo 0
  fi
}

# Gather values
typeset -g PRODUCT_VERSION; PRODUCT_VERSION=$(_sw_val ProductVersion)
typeset -g BUILD; BUILD=$(_sw_val BuildVersion)
typeset -g MODEL_ID; typeset -g CHIP
{ read -r MODEL_ID CHIP } <<EOF
$(_get_hw)
EOF
typeset -g MEM_GB; MEM_GB=$(_get_mem_gb)
typeset -g PRIMARY_VOL; PRIMARY_VOL=$(_primary_volume)
typeset -g DISK_TOTAL_GB; DISK_TOTAL_GB=$(_disk_gb total)
typeset -g DISK_FREE_GB; DISK_FREE_GB=$(_disk_gb free)
typeset -g IFACES_JSON; IFACES_JSON=$(_interfaces_json_fragment)
typeset -g UPTIME_SEC; UPTIME_SEC=$(_uptime_seconds)

if (( MACADMIN_JSON )); then
  printf '{'
  printf '"product_version":"%s"' "$(_json_escape "$PRODUCT_VERSION")"
  printf ',"build":"%s"' "$(_json_escape "$BUILD")"
  printf ',"model_id":"%s"' "$(_json_escape "${MODEL_ID:-}")"
  printf ',"chip":"%s"' "$(_json_escape "${CHIP:-}")"
  printf ',"memory_gb":%s' "${MEM_GB:-0}"
  printf ',"primary_volume":"%s"' "$(_json_escape "$PRIMARY_VOL")"
  printf ',"disk_total_gb":%s' "${DISK_TOTAL_GB:-0}"
  printf ',"disk_free_gb":%s' "${DISK_FREE_GB:-0}"
  printf ',"interfaces":%s' "$IFACES_JSON"
  printf ',"uptime_seconds":%s' "${UPTIME_SEC:-0}"
  printf '}'
  printf '\n'
  exit 0
fi

# Human-readable stable key order
print -r -- "product_version: $PRODUCT_VERSION"
print -r -- "build: $BUILD"
print -r -- "model_id: ${MODEL_ID:-}"
print -r -- "chip: ${CHIP:-}"
print -r -- "memory_gb: ${MEM_GB:-0}"
print -r -- "primary_volume: $PRIMARY_VOL"
print -r -- "disk_total_gb: ${DISK_TOTAL_GB:-0}"
print -r -- "disk_free_gb: ${DISK_FREE_GB:-0}"
print -r -- "interfaces: $IFACES_JSON"
print -r -- "uptime_seconds: ${UPTIME_SEC:-0}"
