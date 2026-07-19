# Migration History

This document tracks what came from where. macadmin is a consolidation of:

- `jenksed/macadmin` (zsh-based, mature architecture; the survivor)
- `jenksed/mac-scripts` (bash-based, broader feature set; migrated in pieces)
- `jenksed/venv-finder` (placeholder repo; the actual code lived in
  `mac-scripts/bin/venv-finder`)

## What came from `jenksed/macadmin`

Every existing command, the dispatcher (`bin/macadmin`), all four
libraries (`lib/{common,argparse,exitcodes,log}.zsh`), the test runner
(`tests/run.zsh`), and 28 mock binaries were carried across unchanged as the
seed of this project.

## What came from `jenksed/mac-scripts`

| Source | Destination | Class |
|---|---|---|
| `LICENSE` (MIT, 2024 Josh Jenks) | `LICENSE` | MERGE |
| `Makefile` (install/uninstall/lint/test/format/dev-setup/new-script/help targets) | `Makefile` | MERGE (extended) |
| `lib/macos.sh` (rich macOS helpers) | `lib/macos.zsh` (new, with `macadmin_` prefix) | MERGE |
| `lib/core.sh` (`backup_file`, `safe_remove`, config loading) | `lib/io.zsh` + `lib/config.zsh` (new) | MERGE |
| `scripts/system/mac-cleanup-sh` (size/age scan) | folded into `macadmin cleanup --older-than --larger-than` (0.3) | REWRITE |
| `scripts/system/scan_screenshots.sh` | `macadmin files organize screenshots` (0.5) | MIGRATE |
| `scripts/files/largest_dirs` | `macadmin disk largest` (0.5) | MIGRATE |
| `scripts/files/find_dupes.sh` + `scripts/files/remove_duplicate_by_hash.sh` | `macadmin disk duplicates [--delete]` (0.5) | REWRITE |
| `scripts/files/rename_files.sh` | `macadmin files rename` (0.5) | REWRITE |
| `scripts/files/sort_by_type.sh` | `macadmin files sort` (0.5) | REWRITE |
| `scripts/files/7zd` + `scripts/files/zip_files.sh` | `macadmin archive create` (0.6) | REWRITE |
| `scripts/files/recompress` | `macadmin archive recompress` (0.6) | REWRITE |
| `scripts/files/optimize_images.sh` | `macadmin media optimize images` (0.6) | REWRITE |
| `scripts/files/optimize_mp4.sh` | `macadmin media optimize mp4` (0.6) | REWRITE |
| `scripts/files/optimize_video.sh` | `macadmin media optimize video` (0.6) | REWRITE |
| `bin/mac-freeze-diagnose` (with `powermmetrics` typo) | `macadmin diagnose freeze` (0.4) | REWRITE |
| `bin/venv-finder` | `macadmin venv-finder` (0.7) | REWRITE |

## What was deliberately dropped

The following scripts from `mac-scripts` were classified as too dangerous to
migrate as-is, with no equivalent in the merged project:

- `scripts/system/clear-system-cache` — broad `sudo rm -rf` without allowlist
- `scripts/system/freeup-memory` — `sudo purge` (trivial; not worth a command)
- `scripts/system/remove-log-files` — broad log deletion without confirmation
- `scripts/system/disable-startup-items` — `launchctl remove` over user items
- `scripts/system/kill-heavy-processes` — `kill -9 $PID` with unquoted PID

The following empty placeholders were deleted (no code, no value):

- `scripts/files/compress_media.sh`
- `scripts/backup/system_backup.sh`
- `scripts/cloud/sync_local_files_to_cloud.sh`
- `scripts/data/csv_to_json_converter.sh`
- `scripts/dev/api_rate_limit_checker.sh`
- `scripts/dev/code_quality_checker.sh`
- `scripts/network/ping_multiple_hosts.sh`
- `scripts/security/automated_system_security_updates.sh`
- `scripts/utils/auto_file_sorter.sh`
- `scripts/utils/automate_deployment_to_aws.sh`
- `scripts/utils/automated_reminder_system.sh`
- `scripts/utils/slack_bot_for_team_notices.sh`

mac-scripts's own dispatcher (`bin/mac-scripts`) was **not** migrated.
The merged project uses only `bin/macadmin`.

mac-scripts's two library files (`lib/core.sh`, `lib/logging.sh`) were not
migrated wholesale. Their useful pieces were ported into macadmin's zsh-based
libraries.

## What was deliberately not carried over

- mac-scripts `curl|bash` install pattern. macadmin uses git clone + `make install`.
- mac-scripts `mac-scripts update` self-update. macadmin uses `git pull` + `make install`.
- mac-scripts README and `docs/install.md`. Replaced by macadmin's
  documentation.

## What was deliberately *added* in macadmin

- `LICENSE` (MIT) — fills a gap; macadmin had none.
- `.gitignore`, `.editorconfig` — basic repo hygiene.
- `.github/workflows/ci.yml` — continuous integration.
- `install.sh` — proper installer with path safety.
- `share/macadminrc.example`, `share/macadminignore.example` — example config.
- `lib/config.zsh` (`~/.macadminrc` loading) — makes the README's config
  claim real.
- `lib/safety.zsh` (allowlist, confirm, within) — centralizes safety.
- `lib/io.zsh` (atomic write, backup, temp dir) — common file ops.
- `MACADMIN_PROTECT` enforcement across mutating commands (release 0.6).

## Standalone `venv-finder`

The `jenksed/venv-finder` GitHub repo contains only a `LICENSE` file — its
code lives at `mac-scripts/bin/venv-finder`. The repo will be archived (no
migration source). The first-class `macadmin venv-finder` command is built
from the mac-scripts version, fully rewritten.

## Detailed reports

For the audit that drove these decisions:

- `reports/repository-audit.md`
- `reports/architecture.md`
- `reports/feature-matrix.md`
- `reports/migration-plan.md`
- `reports/security-review.md`

After 1.0, these reports will be archived and this document becomes the
canonical source of historical context.