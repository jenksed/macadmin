#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

SCRIPT_DIR=${0:a:h}
source "$SCRIPT_DIR/../lib/common.zsh"
require_macos || exit 1

print_header() { print -r -- "\n${C[bold]}$1${C[reset]}"; }

print_header "System Information"

info "OS"
sw_vers || true
printf '\n'

info "Kernel/Hardware"
uname -a || true
system_profiler SPHardwareDataType | awk 'NR<40' || true
printf '\n'

info "Storage"
df -h | awk 'NR==1 || /\/$/' || true
diskutil list | awk 'NR<60' || true
printf '\n'

info "Memory"
sysctl hw.memsize 2>/dev/null | awk '{ printf "Installed: %.2f GB\n", $2/1024/1024/1024 }' || true
vm_stat 2>/dev/null | sed 's/\./\n/g' | awk 'NR<=6' || true
printf '\n'

info "Power"
pmset -g batt 2>/dev/null || echo "No battery info"
printf '\n'

info "Network"
networksetup -listallhardwareports 2>/dev/null || true
ipconfig getifaddr en0 2>/dev/null | sed 's/^/en0 IP: /' || true
ipconfig getifaddr en1 2>/dev/null | sed 's/^/en1 IP: /' || true
scutil --get HostName 2>/dev/null | sed 's/^/HostName: /' || true
scutil --get LocalHostName 2>/dev/null | sed 's/^/LocalHostName: /' || true
scutil --get ComputerName 2>/dev/null | sed 's/^/ComputerName: /' || true

success "Done."

