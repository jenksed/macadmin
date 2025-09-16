# Mac Admin Zsh Scripts

Zsh-based, POSIX-friendly utilities to manage macOS. Includes a dispatcher, shared helpers, and focused subcommands for system info, updates, cleanup, settings, networking, backups, and hardening.

## Layout

```
bin/macadmin               # dispatcher
scripts/*.zsh              # commands
lib/*.zsh                  # shared helpers
share/*.d/*.zsh            # plugin hook dirs (future)

~/.macadminrc              # optional YAML/TOML config
~/.macadminignore          # cleanup allow/ignore patterns
```

## Quick Start

- Use the dispatcher (recommended): `zsh bin/macadmin <command> [args]`
- Or run a script directly: `zsh scripts/system_info.zsh`

Examples:

```
zsh bin/macadmin help
zsh bin/macadmin system-info
zsh bin/macadmin os-update --list
zsh bin/macadmin cleanup --user --dry-run
```

## Global Flags (dispatcher)

Human-readable output by default. The dispatcher parses global flags and exports env toggles for subcommands to honor.

- `--dry-run`: Print actions without executing (also sets `DRY_RUN=1`).
- `--yes`: Assume yes for prompts; allow destructive operations.
- `--verbose`: Increase verbosity (`MACADMIN_VERBOSE=1`).
- `--json`: JSON output where supported (`MACADMIN_JSON=1`).
- `--quiet`: Reduce non-essential output (`MACADMIN_QUIET=1`).
- `--protect`: Extra safety guard for destructive commands (`MACADMIN_PROTECT=1`).

Environment exported to subcommands:

```
MACADMIN_DRY_RUN, MACADMIN_YES, MACADMIN_VERBOSE,
MACADMIN_JSON, MACADMIN_QUIET, MACADMIN_PROTECT
```

Unknown commands exit with code `64` and a suggestion.

## Commands

Each command supports `--help` via its script. A one‑line summary is shown in `macadmin help`.

- `system-info`: Show OS, hardware, storage, network summary.
- `os-update`: List/install macOS updates via `softwareupdate`.
- `cleanup`: Clear caches, rotate logs, run periodic tasks.
- `settings-ui`: Apply sensible Finder/Dock/Text settings.
- `network`: Wi‑Fi on/off, list services, flush DNS.
- `brew-tools`: Check/ensure Homebrew, run `brew bundle`.
- `backup-tmutil`: Time Machine helpers (status, start, list, thin, exclude).
- `hardening`: Enable/disable firewall, Gatekeeper; show security status.

Show per-command help:

```
zsh bin/macadmin <command> --help
```

## Library Helpers

These helpers are safe to `source` multiple times and are used by the dispatcher and all commands.

- `lib/argparse.zsh`: Parse global flags from `$@`.
  - Usage within a script:
    ```
    source lib/argparse.zsh
    macadmin_parse_globals "$@"
    set -- "${MACADMIN_ARGS[@]}"     # remaining args for the command
    ```
  - Behavior: sets/exports `MACADMIN_*`; `--quiet` overrides `--verbose`; sets `DRY_RUN=1` when `--dry-run`.

- `lib/log.zsh`: Logging helpers.
  - Human-readable by default; honors `MACADMIN_QUIET`/`MACADMIN_VERBOSE`.
  - Functions: `log_info`, `log_warn`, `log_error`, `log_debug`, `log_json <event> <payload-json>`, `confirm_or_exit [prompt]`.
  - JSON mode (`MACADMIN_JSON=1`) emits one line per event with stable keys `ts`, `level`, `cmd`, `message`, `data`.
    ```
    MACADMIN_JSON=1 zsh -c 'source lib/log.zsh; log_json update "{\"ok\":true}"'
    # {"ts":"2025-01-01T00:00:00Z","level":"event","cmd":"zsh","message":"update","data":{"ok":true}}
    ```

- `lib/exitcodes.zsh`: Exports sysexits-style constants (e.g., `EX_USAGE=64`).

## Direct Script Execution

Commands accept the same global flags when run directly, thanks to `lib/argparse.zsh` being sourced in each script.

```
zsh scripts/os_update.zsh --list --quiet
zsh scripts/cleanup.zsh --user --dry-run --verbose
MACADMIN_JSON=1 zsh scripts/network.zsh services
```

## Safety & Conventions

- Shell: `zsh` with `setopt errexit nounset pipefail`.
- Idempotent where possible; prefer read-only probes before mutations.
- Destructive actions must be gated by `--yes` and support `--dry-run`.
- `require_sudo` prompts once when a script needs admin rights.
- Scripts should avoid Bashisms unless guarded; aim for POSIX-friendly zsh.

JSON logging is intended for machine consumption of logs and events; command core output remains human-readable unless explicitly documented.

## Developing New Commands

Start from the template for consistent help and flag handling expectations:

```
scripts/_template.zsh
```

The dispatcher extracts a one‑line summary from the usage header (`<file> - <summary>`) for `macadmin help`.

## Testing

Lightweight test runner with mocks is included. Run:

```
make test
```

Golden checks (manual):

```
zsh bin/macadmin help           # lists commands with summaries
zsh bin/macadmin does-not-exist || echo $?   # -> 64
zsh bin/macadmin system-info --help
```

## Notes

- Some commands require admin rights (e.g., system caches, DNS flush, updates).
- Homebrew installation requires network access and user confirmation.
