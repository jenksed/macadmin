#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail
HERE=${0:a:h}
source "$HERE/assert.zsh"

PATH="$HERE/mocks:$PATH" run_cmd R -- zsh scripts/backup_tmutil.zsh status
assert_exit0 $R_STATUS "backup_tmutil: status exits 0"
assert_contains "$R_OUT" "Backup session" "backup_tmutil: shows status"

