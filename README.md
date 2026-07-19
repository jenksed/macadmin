# macadmin

A zsh-based toolkit for macOS administration. One dispatcher, focused
commands, shared libraries, and a safety model that keeps destructive
actions behind explicit gates.

## Why this exists

`macadmin` merges two predecessor projects into one:

- **`jenksed/macadmin`** — the survivor; established the dispatcher + lib
  convention and the `lib/{common,argparse,exitcodes,log,safety,paths,config,macos,io}.zsh`
  architecture.
- **`jenksed/mac-scripts`** — the source of the bulk-rename, sort,
  archive, media-optimize, venv-finder, and mac-cleanup utilities.

The consolidation drops the dangerous `kill-heavy-processes` and
`disable-startup-items` scripts from mac-scripts, lifts the useful
file-management and disk-hygiene helpers into the new architecture, and
documents every command through `--help`, `--dry-run`, `--protect`,
and JSON output.

The full audit is in [`reports/architecture.md`](reports/architecture.md)
and the migration history is in [`docs/migration-history.md`](docs/migration-history.md).

## Install

```sh
git clone https://github.com/jenksed/macadmin.git
cd macadmin
make dev-setup   # installs shellcheck, shfmt, bats-core via brew
make install     # installs into ~/.macadmin/ and symlinks bin/macadmin
```

`make install` honors `INSTALL_DIR=...` and `BIN_DIR=...` for non-default
paths. `make uninstall` reverses it cleanly.

## Quick start

```sh
macadmin help                # list every command with one-line summary
macadmin system-info --json  # stable JSON for dashboards / monitoring
macadmin cleanup --user --dry-run   # preview what would be cleaned
```

Every command supports `--dry-run`, `--json`/`--pretty`, and `--help`.

## Command categories

Each command has a one-line summary visible in `macadmin help` and full
details in [`docs/commands.md`](docs/commands.md).

### System information

| Command | What it does |
|---|---|
| `system-info` | OS / hardware / disk / network / uptime snapshot. Stable JSON for dashboards. |
| `os-update` | List + install macOS updates via `softwareupdate`. |
| `diagnose` | `summary` (read-only snapshot), `cleanup` (file scanner), `freeze` (planning — full execution deferred). |
| `hardening` | Show firewall / Gatekeeper / SIP / FileVault status. |

### Disk + file management

| Command | What it does |
|---|---|
| `cleanup` | Clear user / system caches and logs behind an explicit allowlist. |
| `disk` | `largest` (top-N dirs by size), `duplicates` (sha256 grouping, `--delete` gated). |
| `files` | `rename` (bulk prefix/suffix), `sort` (type-bucket), `organize screenshots`. |
| `venv-finder` | Find Python virtualenvs; validates PEP 405 `pyvenv.cfg` content. |

### Network + packages

| Command | What it does |
|---|---|
| `network` | `services`, `wifi --on/--off`, `dns --flush`, `ping`, `diag --quick`. |
| `brew-tools` | `check`, `ensure`, `bundle`, `doctor`, `list`. |
| `backup-tmutil` | Time Machine helpers: `status`, `start`, `list`, `thin`, `exclude`. |

### Archive

| Command | What it does |
|---|---|
| `archive` | `create` (zip + 7z), `recompress` (zip → 7z). `--delete-sources` is a destructive gate. |

### Settings

| Command | What it does |
|---|---|
| `settings-ui` | Apply sensible Finder / Dock / Text defaults. |

## Three examples per category

### System information

```sh
macadmin system-info --json | jq '{product_version, memory_gb, disk_free_gb}'
macadmin os-update --list
macadmin diagnose summary --json > /tmp/diag.json
```

### Disk + file management

```sh
macadmin cleanup --user --dry-run
macadmin disk largest --path ~ --limit 10 --json
macadmin files sort --path ~/Downloads --dry-run
```

### Network + packages

```sh
macadmin network services --json
macadmin network diag --quick
macadmin brew-tools list --json
```

### Archive

```sh
macadmin archive create ~/Documents/report.pdf --output ~/Desktop/report.zip
macadmin archive create ~/Downloads --format 7z --output logs.7z --delete-sources --yes
macadmin archive recompress ~/Desktop/old.zip --yes
```

### Settings

```sh
macadmin settings-ui --list
macadmin settings-ui apply --dry-run
macadmin settings-ui revert
```

## Architecture (TL;DR)

- `bin/macadmin` is the single dispatcher. It parses global flags, exports
  `MACADMIN_*` env vars, discovers commands via `scripts/*.zsh`, and
  exits `EX_USAGE` (64) with a suggestion on unknown input.
- `lib/*.zsh` are the shared helpers. All are safe to source multiple
  times. The architecture decision record is in
  [`reports/architecture.md`](reports/architecture.md).
- `scripts/*.zsh` are the commands. Each script:
  1. Sources `lib/{common,argparse,exitcodes,log,safety}.zsh`.
  2. Calls `macadmin_parse_globals` to honor global flags.
  3. Honors `--dry-run`, `--yes`, `--protect`, `--json`/`--pretty`.
- `tests/` contains a tap-style runner (`tests/run.zsh`), per-command
  tests (`tests/test_<command>.zsh`), and `tests/mocks/` so commands can
  run under CI without touching the real host.
- `docs/` is the per-command and per-topics reference (see below).
- `reports/` holds the architecture decision record, the migration plan,
  and the retirement plan.

## Safety philosophy

macadmin's default is **read-only**. Every command that can mutate
exposes three orthogonal gates:

- `--dry-run` — print the plan, do nothing.
- `--yes` — confirm destructive operations. Without it, the gate refuses.
- `--protect` — block destructive operations unconditionally, even with `--yes`.
  Set `MACADMIN_PROTECT=1` (or pass `--protect`) to enable.

`make protect-check` runs the protect-enforcement smoke suite in CI:
it verifies every command with a destructive path refuses under
`--protect --yes`. See [`docs/safety.md`](docs/safety.md) for the full
philosophy and [`tests/test_protect_enforcement.zsh`](tests/test_protect_enforcement.zsh)
for the gate tests.

## Development quickstart

1. Create `scripts/<your_command>.zsh` from `scripts/_template.zsh`:
   ```sh
   make new-command NAME=my-cmd   # scaffolds scripts/my_cmd.zsh
   ```
2. Add fixtures to `tests/fixtures/`.
3. Add mocks (if your command shells out) to `tests/mocks/` and make
   them executable.
4. Write `tests/test_my_cmd.zsh` using the `assert.zsh` helpers
   (`run_cmd`, `assert_exit0`, `assert_contains`).
5. Run the full suite:
   ```sh
   make test           # all tests/test_*.zsh
   make coverage       # which commands lack tests
   make protect-check  # MACADMIN_PROTECT gate enforcement
   make lint           # syntax + shellcheck
   ```

Full guide in [`docs/development.md`](docs/development.md) and
[`docs/testing.md`](docs/testing.md).

## Roadmap

- ✅ 0.1 — infrastructure (dispatcher, lib, CI)
- ✅ 0.2 — shared libraries (paths, safety, io, config, macos)
- ✅ 0.3 — core commands (JSON, dry-run, --protect gate)
- ✅ 0.4 — diagnostics (`summary`, `cleanup` scanner, `freeze` planning)
- ✅ 0.5 — disk + file management (`disk largest/duplicates`, `files rename/sort/organize`)
- ✅ 0.6 — archive (`archive create/recompress`) + protect-check smoke
- ✅ 0.7 — venv-finder, network ping, brew polish
- 🔜 0.8 — documentation + final validation
- 🔜 Phase 11 — retire `jenksed/mac-scripts`

Full plan in [`reports/migration-plan.md`](reports/migration-plan.md) and
retirement plan in [`reports/retirement-plan.md`](reports/retirement-plan.md).
