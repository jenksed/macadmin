# Architecture

macadmin is a zsh-based macOS administration toolkit. This document explains
how the pieces fit together. Detailed architectural decisions are in
`reports/architecture.md` (during migration) and will move into this file
post-1.0.

## Layout

```
macadmin/
├── bin/macadmin             # dispatcher
├── scripts/*.zsh            # commands (one per file)
├── lib/*.zsh                # shared helpers
├── share/                   # example config and ignore files
├── tests/                   # zsh test runner + bats library tests + mocks
├── docs/                    # you are here
├── install.sh               # installer
├── Makefile                 # lint, test, install, etc.
├── LICENSE                  # MIT
└── README.md
```

## Dispatcher (`bin/macadmin`)

The dispatcher discovers commands by listing `scripts/*.zsh` (excluding
`_*.zsh`), maps dashed command names to underscored filenames
(`system-info` → `system_info.zsh`), and `exec`s the script with zsh.

Global flags (`--dry-run`, `--yes`, `--verbose`, `--json`, `--quiet`,
`--protect`, `--config`, `--`) are parsed first and exported as
`MACADMIN_*` environment variables so subcommands can honor them without
re-parsing.

Unknown commands exit `EX_USAGE` (64) and suggest the closest match.

## Libraries

| File | Provides |
|---|---|
| `lib/common.zsh` | `info`, `warn`, `error`, `success`, `run`, `require_macos`, `require_cmd`, `require_sudo`, `confirm`, `die` |
| `lib/argparse.zsh` | `macadmin_globals_help`, `macadmin_parse_globals` |
| `lib/exitcodes.zsh` | sysexits(3) constants: `EX_OK`, `EX_USAGE`, `EX_DATAERR`, `EX_NOPERM`, etc. |
| `lib/log.zsh` | `log_info`, `log_warn`, `log_error`, `log_debug`, `log_json`, `confirm_or_exit`, JSON emitters |

Libraries use zsh-idiom guards so multiple `source` calls are safe.

## Command conventions

Every command script:

1. Begins with `#!/usr/bin/env zsh` and `emulate -L zsh`.
2. Sources `lib/common.zsh` + `lib/argparse.zsh` + `lib/exitcodes.zsh` + `lib/log.zsh`.
3. Calls `macadmin_parse_globals "$@"` then re-positions `$@` to remaining args.
4. Calls `require_macos` (tests can mock `uname`).
5. Defines a `usage()` heredoc with a `<file>.zsh - <summary>` first line
   (the dispatcher extracts this for `macadmin help`).
6. Parses command-specific flags, exiting `EX_USAGE` (64) on unknown.
7. Honors `MACADMIN_JSON` (compact) and `MACADMIN_JSON + --pretty` (pretty).
8. Honors `MACADMIN_DRY_RUN` for any mutation.
9. Honors `MACADMIN_PROTECT` + requires `MACADMIN_YES` for any mutation.
10. Exits with a sysexits code, never plain `1`.

## Configuration

User config is read from `~/.macadminrc` (or `--config <path>`). The file is
shell-sourced; `KEY=value` pairs are exposed as `$KEY`. See
`share/macadminrc.example` for the full list of supported keys.

## Testing

Two harnesses:

- **zsh runner** (`tests/run.zsh`) discovers `tests/test_*.zsh`, mocks via
  `tests/mocks/*` injected into `PATH`, runs each test in a subprocess.
- **bats** (`tests/lib/*.bats`) for library-only tests where shell function
  assertions are more comfortable.

Run with `make test`. Coverage with `make coverage`.

## More

- [Safety philosophy](safety.md)
- [Testing](testing.md)
- [Adding a command](development.md)
- [Install / uninstall](install.md)