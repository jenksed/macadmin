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

usage()
{
  cat <<'EOF'
network.zsh - network helpers for macOS

Usage:
  network.zsh services [--list]
  network.zsh wifi --on|--off
  network.zsh dns --flush
  network.zsh ping <host>... [--count N] [--timeout sec]
  network.zsh diag --quick
  # Add --json for machine output; add --pretty to pretty-print JSON.

Flags:
  --dry-run   Print actions without executing
  --yes       Confirm changes (required for wifi on/off unless --dry-run)
  --json      JSON output (line-delimited for lists)
  --verbose   Increase verbosity
  --quiet     Reduce non-essential output

Notes:
  - Wi‑Fi service name can be overridden via ~/.macadminrc:
      YAML: network: { wifi_default_service: "My Wi‑Fi" }
      TOML: [network]\n            wifi_default_service = "My Wi‑Fi"
  - DNS flush tries modern and legacy variants.
  - ping: macOS BSD ping. --count N -> -c N; --timeout SEC -> -W (N*1000) ms.
  - diag --quick performs gateway ping, DNS A/AAAA, and captive portal probe.
EOF
}

# --- Config helpers (best-effort YAML/TOML) ---
_config_get_wifi_service()
{
  local cfg="$HOME/.macadminrc"
  [[ -r "$cfg" ]] || {
    print -r -- ""
    return 0
  }
  # Try TOML: [network] then wifi_default_service = "..."
  local val
  val=$(awk '
    BEGIN{insec=0}
    /^\s*\[network\]\s*$/ {insec=1; next}
    /^\s*\[/ {if(insec){exit} insec=0}
    insec && /wifi_default_service/ {
      # Accept: key = "value" or key = value
      s=$0
      sub(/.*wifi_default_service[^=]*=\s*/, "", s)
      gsub(/^"|"\s*#.*$/,"",s)
      gsub(/^'\''|'\''\s*#.*$/,"",s)
      gsub(/#.*/ ,"", s)
      gsub(/^\s+|\s+$/ ,"", s)
      print s; exit
    }
  ' "$cfg" 2>/dev/null || true)
  if [[ -n "$val" ]]; then
    print -r -- "$val"
    return 0
  fi
  # Try YAML: network: ... then wifi_default_service: value
  val=$(awk '
    BEGIN{insec=0}
    /^\s*network\s*:\s*$/ {insec=1; next}
    /^[^[:space:]].*:/{if(insec){exit} insec=0}
    insec && /wifi_default_service\s*:/ {
      s=$0
      sub(/.*wifi_default_service\s*:\s*/,"",s)
      gsub(/^"|"\s*#.*$/,"",s)
      gsub(/^'\''|'\''\s*#.*$/,"",s)
      gsub(/#.*/ ,"", s)
      gsub(/^\s+|\s+$/ ,"", s)
      print s; exit
    }
  ' "$cfg" 2>/dev/null || true)
  print -r -- "$val"
}

# --- networksetup helpers ---
_ns_services()
{
  # Prints: "<enabled>\t<service>"
  networksetup -listallnetworkservices 2>/dev/null | awk '
    NR==1 {next} # skip header line
    NF==0 {next}
    {
      s=$0
      gsub(/^\*\s*/ ,"", s)
      enabled = ($0 !~ /^\*/) ? "1" : "0"
      print enabled "\t" s
    }
  '
}

_ns_find_wifi_service()
{
  local override
  override=$(_config_get_wifi_service)
  if [[ -n "$override" ]]; then
    if _ns_services | awk -v s="$override" 'BEGIN{ok=0} $2==s{ok=1} END{exit(ok?0:1)}'; then
      print -r -- "$override"
      return 0
    fi
    log_warn "Configured wifi_default_service not found: $override"
  fi
  # Try to map from service order: service line followed by Hardware Port containing Wi-Fi/AirPort
  local prev="" found=""
  local out
  if out=$(networksetup -listnetworkserviceorder 2>/dev/null); then
    while IFS= read -r line; do
      case "$line" in
        \(*\)*) prev=${${line##*) }% } ;;
        *Hardware\ Port:*)
          if [[ "$line" == *Wi-Fi* || "$line" == *AirPort* ]]; then
            found="$prev"
            break
          fi
          ;;
      esac
    done <<<"$out"
    if [[ -n "$found" ]]; then
      print -r -- "$found"
      return 0
    fi
  fi
  # Fallback: first service whose name includes Wi-Fi/AirPort
  _ns_services | awk '$2 ~ /Wi-Fi|AirPort/ {print $2; exit}'
}

_ns_device_for_service()
{
  local svc="$1" out prev dev=""
  if out=$(networksetup -listnetworkserviceorder 2>/dev/null); then
    while IFS= read -r line; do
      case "$line" in
        \(*\)*) prev=${${line##*) }% } ;;
        *Hardware\ Port:*)
          if [[ "$prev" == "$svc" ]]; then
            dev=${${line##*Device: }%)}
            break
          fi
          ;;
      esac
    done <<<"$out"
  fi
  if [[ -z "$dev" && "$svc" == *Wi-Fi* || -z "$dev" && "$svc" == *AirPort* ]]; then
    dev=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/{f=1} f&&/Device:/{print $2; exit}')
  fi
  print -r -- "$dev"
}

# Ping one host, parse BSD ping stats, emit JSON or human output.
# Echoes nothing on stdout besides the formatted output (no scope leaks).
# Args: <host> <count> [<ping_arg>...]
# Returns: 0 if reachable, 1 otherwise (BSD ping semantics).
#
# NOTE: function scope is essential. The same `local x; x=$(...)` pattern
# inside a `for` loop body would leak `x=value` at scope-end (zsh quirk).
_network_ping_one()
{
  emulate -L zsh
  set +o errexit  # ping may legitimately exit non-zero
  local host="$1"; shift
  local count="$1"; shift
  local pout rc
  pout="$(ping "$@" "$host" 2>/dev/null)"
  rc=$?
  # BSD ping stats line:  "1 packets transmitted, 1 packets received, 0.0% packet loss"
  # Tokenize by whitespace. Find "packets" followed by "transmitted," or
  # "received,"; the field BEFORE "packets" is the count.
  local tx rx loss
  tx="$(print -r -- "$pout" | awk '
    /packets transmitted/ {
      for (i=1;i<=NF;i++) if ($i=="packets" && $(i+1)=="transmitted,") {
        print $(i-1); exit
      }
    }')"
  rx="$(print -r -- "$pout" | awk '
    /packets received/ {
      for (i=1;i<=NF;i++) if ($i=="packets" && $(i+1)=="received,") {
        print $(i-1); exit
      }
    }')"
  loss="$(print -r -- "$pout" | awk '
    /packet loss/ {
      for (i=1;i<=NF;i++) if ($i=="packet" && $(i+1)=="loss") {
        v=$(i-1); gsub(/%/,"",v); print v; exit
      }
    }')"
  # Round-trip line:  "round-trip min/avg/max/stddev = 0.123/0.123/0.123/0.000 ms"
  # Split on `=` AND `/`. After "round-trip min/avg/max/stddev " comes the
  # `=` then space then the 4 numbers. They land at $5..$8 ($5 has a
  # leading space because of the `=` followed by whitespace).
  local stats
  stats="$(print -r -- "$pout" | awk -F'[=/]' '
    /min\/avg\/max/ {
      gsub(/^[ \t]+/, "", $5)
      gsub(/[ \t]+ms$/, "", $8)
      print $5"/"$6"/"$7"/"$8; exit
    }')"
  local min avg max mdev
  if [[ -n "$stats" ]]; then
    IFS='/' read -r min avg max mdev <<<"$stats"
  fi
  # Defaults for missing fields (unreachable host emits only failure lines).
  : "${tx:=0}" "${rx:=0}" "${loss:=100}" "${min:=}" "${avg:=}" "${max:=}" "${mdev:=}"

  local ok=false
  (( rc == 0 )) && ok=true

  if ((MACADMIN_JSON)); then
    local kv
    kv=(
      host="$host"
      transmitted="$tx"
      received="$rx"
      packet_loss="$loss"
      min_ms="$min"
      avg_ms="$avg"
      max_ms="$max"
      ok="$ok"
    )
    if ((opt_pretty)); then
      macadmin_json_pretty_obj "$kv[@]"
      printf '\n'
    else
      macadmin_json_obj "$kv[@]"
      printf '\n'
    fi
  else
    local packet_word="packet"
    (( count != 1 )) && packet_word="packets"
    log_info "Pinging $host (${count} $packet_word)..."
    [[ -n "$pout" ]] && print -r -- "$pout"
    if (( rc == 0 )); then
      log_info "$host: $rx/$tx received (${loss}% loss) min/avg/max = ${min}/${avg}/${max} ms"
    else
      log_warn "$host: unreachable (rc=$rc)"
    fi
  fi

  return $rc
}

# --- JSON helpers (from lib/log.zsh) ---
# Using macadmin_json_obj and macadmin_json_pretty_obj

# --- Subcommands ---

typeset -i opt_pretty=0

# Detect optional --pretty anywhere in args (non-global)
for a in "$@"; do
  case "$a" in
    --pretty) opt_pretty=1 ;;
  esac
done

subcmd=${1:-}
case "$subcmd" in
  -h | --help | help | "")
    usage
    exit 0
    ;;

  services)
    # Backward-compatible: no --list flag needed
    log_info "Listing network services..."
    if ((MACADMIN_JSON)); then
      if ((opt_pretty)); then
        # Aggregate and pretty print as one JSON object with array
        printf '{\n  "services": [\n'
        local first=1
        while IFS=$'\t' read -r en svc; do
          [[ -z "$svc" ]] && continue
          if ((first)); then first=0; else printf ' ,\n'; fi
          printf '    '
          macadmin_json_pretty_obj service="$svc" enabled=$([[ "$en" == 1 ]] && echo true || echo false)
        done < <(_ns_services)
        printf '\n  ]\n}\n'
      else
        while IFS=$'\t' read -r en svc; do
          [[ -z "$svc" ]] && continue
          macadmin_json_obj service="$svc" enabled=$([[ "$en" == 1 ]] && echo true || echo false)
          printf '\n'
        done < <(_ns_services)
      fi
    else
      networksetup -listallnetworkservices
    fi
    ;;

  wifi)
    shift || true
    local state=""
    case "${1:-}" in
      --on | on) state=on ;;
      --off | off) state=off ;;
      -h | --help | "")
        usage
        exit 0
        ;;
      *)
        log_error "wifi expects --on or --off"
        usage
        exit ${EX_USAGE:-64}
        ;;
    esac

    local svc dev
    svc=$(_ns_find_wifi_service)
    [[ -n "$svc" ]] || {
      log_error "Unable to determine Wi‑Fi service name"
      exit ${EX_UNAVAILABLE:-69}
    }
    dev=$(_ns_device_for_service "$svc")

    # Safety-by-default
    if ((MACADMIN_PROTECT)) && ((!MACADMIN_YES)); then
      log_error "Refusing to change Wi‑Fi state under --protect without --yes."
      exit ${EX_NOPERM:-77}
    fi
    if ((!MACADMIN_DRY_RUN)) && ((!MACADMIN_YES)); then
      log_error "Refusing to change Wi‑Fi state without --yes. Use --dry-run to preview."
      exit ${EX_NOPERM:-77}
    fi

    if ((MACADMIN_JSON)); then
      macadmin_json_obj action="wifi" service="$svc" device="$dev" state="$state"
      printf '\n'
    else
      log_info "Setting Wi‑Fi ($svc${dev:+/$dev}) $state"
    fi

    if ((MACADMIN_DRY_RUN)); then
      if [[ -n "$dev" ]]; then
        run networksetup -setairportpower "$dev" "$state"
      else
        run networksetup -setnetworkserviceenabled "$svc" "$state"
      fi
      exit 0
    fi

    if [[ -n "$dev" ]]; then
      run networksetup -setairportpower "$dev" "$state"
    else
      run networksetup -setnetworkserviceenabled "$svc" "$state"
    fi
    ;;

  dns)
    shift || true
    case "${1:-}" in
      --flush | flush)
        log_info "Flushing DNS caches (modern + legacy variants)..."
        # Modern variants
        run dscacheutil -flushcache || true
        if ((MACADMIN_DRY_RUN)); then
          run sudo killall -HUP mDNSResponder || true
          run sudo killall -HUP mDNSResponderHelper || true
          run sudo discoveryutil udnsflushcaches || true
        else
          require_sudo
          run sudo killall -HUP mDNSResponder || true
          run sudo killall -HUP mDNSResponderHelper || true
          run sudo discoveryutil udnsflushcaches || true
        fi
        if ((MACADMIN_JSON)); then
          if ((opt_pretty)); then
            macadmin_json_pretty_obj action="dns_flush" ok=true
            printf '\n'
          else
            macadmin_json_obj action="dns_flush" ok=true
            printf '\n'
          fi
        fi
        ;;
      -h | --help | "")
        usage
        exit 0
        ;;
      *)
        log_error "Unknown dns subcommand"
        usage
        exit ${EX_USAGE:-64}
        ;;
    esac
    ;;

  ping)
    shift
    typeset -a hosts=()
    typeset -i opt_count=1
    typeset -i opt_timeout_ms=0
    while (( $# > 0 )); do
      case "$1" in
        -c|--count)
          (( $# >= 2 )) || { log_error "ping: --count requires a value"; exit ${EX_USAGE:-64}; }
          opt_count=$2; shift 2 ;;
        -W|--timeout)
          (( $# >= 2 )) || { log_error "ping: --timeout requires a value"; exit ${EX_USAGE:-64}; }
          # Accept seconds (per docs); pass to BSD ping -W as ms.
          opt_timeout_ms=$(( $2 * 1000 )); shift 2 ;;
        -h|--help)
          usage; exit 0 ;;
        --json|--pretty|--quiet|--verbose|--dry-run|--yes) shift ;;
        --) shift; hosts+=("$@"); break ;;
        -*)
          log_error "ping: unknown flag: $1"
          exit ${EX_USAGE:-64} ;;
        *)
          hosts+=("$1"); shift ;;
      esac
    done
    if (( ${#hosts[@]} == 0 )); then
      log_error "ping: at least one host required"
      exit ${EX_USAGE:-64}
    fi
    if (( opt_count < 1 )); then
      log_error "ping: --count must be >= 1"
      exit ${EX_USAGE:-64}
    fi

    # Build the ping arg list once. -W is omitted when timeout is 0 so we
    # do not surprise BSD ping with a zero wait.
    typeset -a ping_args=(-c "$opt_count")
    if (( opt_timeout_ms > 0 )); then
      ping_args+=(-W "$opt_timeout_ms")
    fi

    typeset -i any_fail=0
    for host in "${hosts[@]}"; do
      _network_ping_one "$host" "$opt_count" "${ping_args[@]}"
      (( $? != 0 )) && any_fail=1
    done

    # Exit non-zero if any host failed (matches BSD ping semantics:
    # rc=1 means some packets lost; rc=2 means fatal error).
    if (( any_fail )); then
      exit ${EX_TEMPFAIL:-75}
    fi
    ;;

  diag)
    shift || true
    case "${1:-}" in
      --quick | quick)
        if ((MACADMIN_DRY_RUN)); then
          log_info "Dry-run: would ping gateway, resolve A/AAAA, and probe captive portal."
          exit 0
        fi
        local gw="" ping_ok=false a_ok=false aaaa_ok=false captive_ok=false
        # default gateway
        gw=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2;exit}') || gw=""
        [[ -z "$gw" ]] && gw=$(netstat -rn 2>/dev/null | awk '/^default/{print $2; exit}') || true
        if [[ -n "$gw" ]]; then
          if ping -c 1 -n "$gw" >/dev/null 2>&1; then ping_ok=true; fi
        fi
        # DNS resolve checks
        if dscacheutil -q host -a name apple.com 2>/dev/null | awk '/^ip_address:/{f=1} END{exit(f?0:1)}'; then a_ok=true; fi
        if dscacheutil -q host -a name apple.com 2>/dev/null | awk '/^ipv6_address:/{f=1} END{exit(f?0:1)}'; then aaaa_ok=true; fi
        # captive portal probe
        local code=0
        code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 5 http://captive.apple.com/hotspot-detect.html 2>/dev/null || echo 0)
        if [[ "$code" == 200 ]]; then captive_ok=true; fi

        if ((MACADMIN_JSON)); then
          local kv
          kv=(
            check="quick"
            gateway="$gw"
            ping_ok=$([[ $ping_ok == true ]] && echo true || echo false)
            dns_a_ok=$([[ $a_ok == true ]] && echo true || echo false)
            dns_aaaa_ok=$([[ $aaaa_ok == true ]] && echo true || echo false)
            captive_ok=$([[ $captive_ok == true ]] && echo true || echo false)
          )
          if ((opt_pretty)); then
            macadmin_json_pretty_obj "$kv[@]"
            printf '\n'
          else
            macadmin_json_obj "$kv[@]"
            printf '\n'
          fi
        else
          log_info "Gateway: ${gw:-unknown} (reachable: $([[ $ping_ok == true ]] && echo yes || echo no))"
          log_info "DNS A(apple.com): $([[ $a_ok == true ]] && echo ok || echo fail)  AAAA: $([[ $aaaa_ok == true ]] && echo ok || echo fail)"
          log_info "Captive portal: $([[ $captive_ok == true ]] && echo ok || echo fail)"
        fi
        # Exit code: success only if all essentials pass (gateway ping + any DNS + captive optional?)
        if [[ $ping_ok == true && ($a_ok == true || $aaaa_ok == true) ]]; then
          exit 0
        else
          exit ${EX_TEMPFAIL:-75}
        fi
        ;;
      -h | --help | "")
        usage
        exit 0
        ;;
      *)
        log_error "Unknown diag subcommand"
        usage
        exit ${EX_USAGE:-64}
        ;;
    esac
    ;;

  *)
    usage
    exit ${EX_USAGE:-64}
    ;;
esac

# If we get here, subcommand executed.
exit 0
