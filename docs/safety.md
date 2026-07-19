# Safety

macadmin is designed to do powerful things safely. The toolkit can install
updates, mutate user preferences, thin Time Machine snapshots, toggle
firewall, and remove files. Every mutating action is gated.

## The three gates

| Gate | Env var | Effect |
|---|---|---|
| `--dry-run` | `MACADMIN_DRY_RUN=1` | Print the plan; do not execute. |
| `--yes` | `MACADMIN_YES=1` | Skip confirmation prompts. |
| `--protect` | `MACADMIN_PROTECT=1` | Refuse to mutate without `--yes` — even if `--yes` was passed. |

**Default behavior:** no flag is set, so:

- Dry-run is off — actions execute when invoked.
- Prompts appear for destructive actions.
- `--protect` is off — `--yes` is enough.

## Allowlists

`macadmin cleanup` only deletes within an explicit allowlist of roots.
Even within an allowed root, paths matching `~/.macadminignore` are
skipped. The allowlist is documented in `scripts/cleanup.zsh`.

## Exit codes

macadmin uses [sysexits(3)](https://man.openbsd.org/sysexits) conventions.
Relevant codes:

- `0` (`EX_OK`) — success
- `64` (`EX_USAGE`) — bad invocation (unknown flag, missing arg)
- `65` (`EX_DATAERR`) — input data is wrong
- `66` (`EX_NOINPUT`) — file or directory does not exist
- `69` (`EX_UNAVAILABLE`) — required tool missing
- `70` (`EX_SOFTWARE`) — internal command error
- `73` (`EX_CANTCREAT`) — cannot create output
- `77` (`EX_NOPERM`) — refusing to proceed without `--yes` or sudo
- `78` (`EX_CONFIG`) — config error

## `--protect` enforcement

Every mutating command must:

```zsh
if (( MACADMIN_PROTECT )) && (( ! MACADMIN_YES )); then
  log_error "refusing to mutate under --protect without --yes"
  exit ${EX_NOPERM:-77}
fi
```

This is verified by `make protect-check`.

## Privacy

- Serial numbers and hardware UUIDs are not emitted by default. Pass
  `--identifiers` to `macadmin system-info` to reveal them.
- `macadmin diagnose freeze` produces a bundle that may contain personal
  information (file paths, login timestamps). The bundle is written to the
  user-specified output directory — never `~/Desktop` automatically.

## Reporting safety issues

Please open a GitHub issue with `[SECURITY]` in the title for any safety
concerns. The maintainer triages these within 48 hours.