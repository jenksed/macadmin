# Command Reference

Per-command reference generated from each script's `--help` output,
plus curated examples and safety notes. For machine-readable output,
every command supports `--json` (and `--pretty` where the output is a
single object).

## Quick index

| Command | Category | One-line |
|---|---|---|
| `archive` | Archive | Bundle sources into zip / 7z; recompress zip → 7z. |
| `backup-tmutil` | Backup | Time Machine helpers (status, start, list, thin, exclude). |
| `brew-tools` | Packages | Detect Homebrew; run `brew bundle`, `doctor`, `list`. |
| `cleanup` | Disk | Clear caches, rotate logs behind an allowlist. |
| `diagnose` | System info | `summary` snapshot, `cleanup` scanner, `freeze` planning. |
| `disk` | Disk | `largest` (top-N dirs by size); `duplicates` (sha256 grouping). |
| `files` | Disk | `rename`, `sort`, `organize screenshots` — destructive gates. |
| `hardening` | System info | Show firewall / Gatekeeper / SIP / FileVault status. |
| `network` | Network | `services`, `wifi`, `dns`, `ping`, `diag`. |
| `os-update` | System info | List + install macOS updates via `softwareupdate`. |
| `settings-ui` | Settings | Apply sensible Finder / Dock / Text defaults. |
| `system-info` | System info | OS / hardware / disk / network / uptime snapshot. |
| `venv-finder` | Disk | Find Python virtualenvs (PEP 405 `pyvenv.cfg` validator). |

## Global flags (every command)

| Flag | Meaning |
|---|---|
| `--dry-run` | Print the plan, do nothing. Sets `DRY_RUN=1`. |
| `--yes` | Confirm destructive operations. |
| `--protect` | Block destructive operations unconditionally (even with `--yes`). Sets `MACADMIN_PROTECT=1`. |
| `--json` | Compact JSON output (one line per object). |
| `--pretty` | Pretty-printed JSON (single object or array). |
| `--verbose` | Increase verbosity (`MACADMIN_VERBOSE=1`). |
| `--quiet` | Reduce non-essential output (`MACADMIN_QUIET=1`). |

Safety note: the dispatcher refuses unknown commands with exit code 64
(`EX_USAGE`) and prints a "did you mean" suggestion when applicable.

---

## archive

Bundle sources into a zip or 7z archive. Recompress an existing zip
into a smaller 7z archive. `zip` is built into macOS; `7z` requires
`brew install p7zip`.

```
Usage:
  archive create <sources...> [--output <path>] [--format 7z|zip]
                          [--delete-sources] [--yes] [--protect]
                          [--dry-run] [--json|--pretty]
  archive recompress <input> [--output <path>] [--yes]
```

Flags: `--output <path>`, `--format 7z|zip` (default `zip`),
`--delete-sources`, `--dry-run`, `--json|--pretty`, `--yes`,
`--protect`.

Examples:

```sh
macadmin archive create ~/Documents/report.pdf --output ~/Desktop/report.zip
macadmin archive create ~/Downloads --format 7z --output logs.7z --delete-sources --yes
macadmin archive recompress ~/Desktop/old.zip --output ~/Desktop/old.7z --yes
```

Safety: `--delete-sources` and `--no-dry-run` are destructive; both
require `--yes` and are blocked by `--protect`. Missing 7z → exit 69
(`EX_UNAVAILABLE`).

---

## backup-tmutil

Time Machine helpers.

```
Usage:
  backup-tmutil status [--json|--pretty]
  backup-tmutil start|stop
  backup-tmutil list [--json]
  backup-tmutil thin <size>
  backup-tmutil exclude <path>
```

Examples:

```sh
macadmin backup-tmutil status
macadmin backup-tmutil start
macadmin backup-tmutil exclude ~/Downloads
```

Safety: `start`/`stop` require `sudo`; `exclude` and `thin` are
persistent (you must remember to re-add excluded paths). Always
`status` first.

---

## brew-tools

Detect, ensure, and operate on Homebrew. Wraps `brew` with macadmin's
safety gates.

```
Usage:
  brew_tools check
  brew_tools ensure [--yes] [--dry-run]
  brew_tools bundle --generate|--diff|--apply [--dry-run]
  brew_tools doctor [--json]
  brew_tools list [--json]
```

Examples:

```sh
macadmin brew-tools check
macadmin brew-tools list --json | jq '.[] | .formula'
macadmin brew-tools doctor --json
```

Safety: `ensure` and `bundle --apply` are destructive. `doctor` and
`list` are read-only.

---

## cleanup

Clear user / system caches and logs behind an explicit allowlist.

```
Usage:
  cleanup --user|--system|--all [--older-than <days>] [--larger-than <size>]
         [--yes] [--dry-run] [--json|--pretty]
```

Flags: `--older-than <days>`, `--larger-than <size>`, `--yes`,
`--dry-run`, `--json|--pretty`, `--protect`.

Examples:

```sh
macadmin cleanup --user --dry-run
macadmin cleanup --user --older-than 30
macadmin cleanup --all --larger-than 100M
```

Safety: all mutations are allowlisted via `lib/safety.zsh`. `--protect`
blocks destructive actions.

---

## diagnose

Read-only system snapshot + file scanner + freeze planning. Full
`freeze` execution (sample / spindump / log show) is deferred to a
follow-up release — requires `sudo` and is hard to test cleanly in CI.

```
Usage:
  diagnose summary [--json|--pretty]
  diagnose cleanup [--path <root>] [--older-than <days>]
                  [--larger-than <size>] [--json|--pretty]
  diagnose freeze --dry-run
```

Flags: `--path`, `--older-than`, `--larger-than`, `--json|--pretty`,
`--dry-run`.

Examples:

```sh
macadmin diagnose summary --json > /tmp/diag.json
macadmin diagnose cleanup --path ~/Downloads --older-than 30
macadmin diagnose freeze --dry-run
```

Safety: `summary` and `freeze --dry-run` are read-only. `cleanup` only
*scans* — it never deletes.

---

## disk

Find the largest directories and detect duplicate files.

```
Usage:
  disk largest   [--path <root>] [--limit N] [--json|--pretty]
  disk duplicates [--path <root>] [--delete] [--yes] [--protect]
                  [--json|--pretty]
```

Flags: `--path`, `--limit N` (default 20), `--delete`, `--yes`,
`--protect`, `--json|--pretty`.

Examples:

```sh
macadmin disk largest --path ~ --limit 10 --json
macadmin disk duplicates --path ~/Downloads --json
macadmin disk duplicates --path ~/Downloads --delete --yes
```

Safety: `--delete` requires `--yes` and is blocked unconditionally by
`--protect`. Hashing every file under a large path can take minutes.

---

## files

File management: bulk rename, type-bucketed sort, screenshot organize.

```
Usage:
  files rename <pattern> [--prefix X] [--suffix Y] [--dry-run]
  files sort [--path <dir>] [--dry-run]
  files organize screenshots [--dest <dir>] [--dry-run]
```

Flags: `--prefix`, `--suffix`, `--dry-run`, `--path`, `--dest`,
`--yes`, `--protect`.

Examples:

```sh
macadmin files rename "*.txt" --prefix "old_"
macadmin files sort --path ~/Downloads --dry-run
macadmin files organize screenshots --dest ~/Pictures/Screenshots
```

Safety: `sort` is restricted to `~/Downloads`, `~/Desktop`, or
`~/Documents` (the user drop-zone allowlist). `--no-dry-run` requires
`--yes` and is blocked by `--protect`.

---

## hardening

Show firewall / Gatekeeper / SIP / FileVault status.

```
Usage:
  hardening status [--json|--pretty]
```

Examples:

```sh
macadmin hardening status
macadmin hardening status --json | jq '.'
```

Safety: read-only. Future releases may add `enable`/`disable` modes
behind `--protect`.

---

## network

Network helpers: services, Wi‑Fi on/off, DNS flush, ping, diagnostic.

```
Usage:
  network services [--list] [--json]
  network wifi --on|--off [--dry-run] [--yes] [--protect]
  network dns --flush [--dry-run] [--yes] [--protect]
  network ping <host>... [--count N] [--timeout sec] [--json]
  network diag --quick [--json]
```

Flags: `--dry-run`, `--yes`, `--protect`, `--json|--pretty`.

Examples:

```sh
macadmin network services --json
macadmin network wifi --off --dry-run
macadmin network diag --quick
```

Safety: `wifi`, `dns`, and `diag` are destructive or state-changing.
All are gated by `--yes` and blocked by `--protect`.

---

## os-update

List + install macOS updates via `softwareupdate`.

```
Usage:
  os-update --list [--json]
  os-update --install [--yes] [--protect]
```

Flags: `--list`, `--install`, `--yes`, `--protect`.

Examples:

```sh
macadmin os-update --list
macadmin os-update --install --yes
```

Safety: `--install` requires `sudo` and `--yes`. `--protect` blocks
installation.

---

## settings-ui

Apply sensible Finder / Dock / Text defaults.

```
Usage:
  settings-ui --list
  settings-ui apply [--dry-run] [--yes]
  settings-ui revert
```

Examples:

```sh
macadmin settings-ui --list
macadmin settings-ui apply --dry-run
```

Safety: `apply` writes user defaults via `defaults write`; gated by
`--yes`.

---

## system-info

Stable OS / hardware / disk / network / uptime snapshot. Stable JSON
key order is part of the public contract — downstream tools may depend
on it.

```
Usage:
  system-info [--json|--pretty]
```

Examples:

```sh
macadmin system-info --json | jq '{product_version, memory_gb, disk_free_gb}'
macadmin system-info --pretty
```

Safety: read-only. No mutations.

---

## venv-finder

Find Python virtualenvs. Validates that `pyvenv.cfg` contains the
PEP 405 `home =` directive (refuses poisoned / stale `pyvenv.cfg` files
without it).

```
Usage:
  venv-finder [--path <root>] [--json|--pretty]
              [--min-size <bytes>] [--ignore <pattern>...]
              [--limit N]
```

Flags: `--path`, `--min-size`, `--ignore`, `--limit`, `--json|--pretty`.

Examples:

```sh
macadmin venv-finder --json | jq '.path'
macadmin venv-finder --path ~/Projects --limit 20
```

Safety: read-only discovery. Junk dirs (`.git`, `node_modules`,
`__pycache__`, `Library/Caches`) are pruned automatically.
