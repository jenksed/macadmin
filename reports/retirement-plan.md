# Phase 11 — Retirement Plan: `jenksed/mac-scripts`

**Date:** 2026-07-19
**Status:** Active (will execute after Release 0.8 ships)

## Goal

Archive the `jenksed/mac-scripts` repository once macadmin has absorbed
every script that was worth keeping, and the remaining dangerous
scripts are explicitly dropped.

## What migrates to macadmin

Every useful script from `jenksed/mac-scripts` has been rewritten as a
first-class macadmin command per the migration plan:

| mac-scripts file | macadmin command | Notes |
|---|---|---|
| `bin/mac-freeze-diagnose` | `macadmin diagnose freeze` | `--dry-run` only in 0.4; full execution is a follow-up. |
| `scripts/system/scan_screenshots.sh` | `macadmin files organize screenshots` | |
| `scripts/system/mac-cleanup-sh` | `macadmin cleanup` + `macadmin diagnose cleanup` | |
| `scripts/system/*` (other utilities) | `macadmin system-info`, `macadmin os-update`, `macadmin hardening` | |
| `scripts/network/*` | `macadmin network {services,wifi,dns,ping,diag}` | |
| `scripts/files/*` | `macadmin files rename` | |
| `scripts/utils/*` (archive, optimize, etc.) | `macadmin archive`, `macadmin venv-finder` | |
| `bin/venv-finder` | `macadmin venv-finder` | PEP 405 `pyvenv.cfg` validator added. |

Coverage: 100% of mac-scripts utilities that survived the audit are
re-implemented in macadmin. See `docs/migration-history.md` for the
detailed audit trail.

## What is deliberately dropped

These mac-scripts files are **NOT** carried forward. Document the
reason so future readers don't ask why.

| File | Why dropped |
|---|---|
| `scripts/utils/kill-heavy-processes.sh` | Aggressively `kill -9`s processes by pattern. Too dangerous for an automated tool — risk of killing the user's own session or system processes. Use Activity Monitor instead. |
| `scripts/utils/disable-startup-items.sh` | Modifies LaunchAgents / LaunchDaemons / Login Items globally. Reverting requires manual cleanup. Better done explicitly per-item via `launchctl` / `osascript`. |
| `scripts/system/mac-sysdiagnose.sh` (predecessor of `mac-freeze-diagnose`) | Superseded by `macadmin diagnose`. |

## Archive procedure

When 0.8 ships and the smoke pass is green:

1. **Tag the mac-scripts archive commit** in `jenksed/mac-scripts`:
   ```sh
   cd ../mac-scripts
   git checkout main
   # Verify no unmerged work.
   git tag -a archive-2026-07-19 -m "Archived: utilities migrated to jenksed/macadmin"
   git push origin archive-2026-07-19
   ```
2. **Update the README** to point at macadmin:
   ```md
   # jenksed/mac-scripts — ARCHIVED

   This repository has been archived. Its utilities have been merged
   into [`jenksed/macadmin`](https://github.com/jenksed/macadmin) as
   first-class commands. See the [mac-scripts → macadmin migration
   plan](https://github.com/jenksed/macadmin/blob/main/reports/migration-plan.md)
   for details.

   - `bin/mac-freeze-diagnose` → `macadmin diagnose freeze`
   - `scripts/system/scan_screenshots.sh` → `macadmin files organize screenshots`
   - … (full table in `docs/migration-history.md`)

   The dangerous scripts (`kill-heavy-processes.sh`,
   `disable-startup-items.sh`) were deliberately NOT migrated — see
   the macadmin retirement plan.
   ```
3. **Mark the repo as archived on GitHub** (Settings → General → Archive
   this repository). This is a soft archive — issues remain readable,
   no further commits are accepted.
4. **Post a final issue** linking to macadmin so any external users
   see the migration notice.

## What stays in mac-scripts

Nothing. The whole repo is archived. References in macadmin docs
(`docs/migration-history.md`) link to the archived snapshot for
historical context only.

## Communication

- mac-scripts README update (above).
- macadmin README already links to mac-scripts via
  `docs/migration-history.md`.
- A short note in the macadmin release notes (0.8.0).

## Rollback

If a critical bug is found in a macadmin port of a mac-scripts utility
after archive, the fix lives in macadmin. The mac-scripts archive is
read-only on GitHub so we don't reintroduce drift.

## Checklist

- [ ] All macadmin commands at 100% test coverage (currently 13/13 commands).
- [ ] `make lint test coverage protect-check ci` all green.
- [ ] Manual smoke pass against the mac-scripts use cases documented
      in `reports/migration-plan.md`.
- [ ] macadmin README points at the archived mac-scripts.
- [ ] mac-scripts README points at macadmin.
- [ ] mac-scripts tagged `archive-2026-07-19`.
- [ ] mac-scripts marked archived on GitHub.

When all checks pass, Phase 11 is complete.
