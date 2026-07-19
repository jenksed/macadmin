# Troubleshooting

## `macadmin: command not found`

After `make install`, the dispatcher symlink should be at `~/bin/macadmin`.

```bash
ls -l ~/bin/macadmin
```

If it's missing:

```bash
make link
```

If `~/bin` isn't on your `PATH`:

```bash
grep -F '# macadmin PATH' ~/.zshrc || echo "PATH marker missing"
make install  # re-appends the marker
```

## `zsh: command not found: shellcheck`

Install dev tools:

```bash
make dev-setup
```

## `macadmin help` shows no commands

Your `scripts/` directory is empty or missing. Verify:

```bash
ls scripts/*.zsh
```

If you cloned via `git clone`, all scripts should be present. If you
copied a subset, re-clone.

## `macadmin cleanup --user --dry-run` says "Refusing to remove outside allowlist"

Good — that's the safety net. Add the path to your allowlist by editing
`~/.macadminrc`:

```bash
CLEANUP_ALLOWLIST_EXTRA="$HOME/work/cache:$HOME/scratch/temp"
```

Or skip it by adding the specific path to `~/.macadminignore` as an
`!`-prefixed unignore line.

## `macadmin system-info --json` returns empty

Some commands require interactive input. Run with `--pretty` for human
readable:

```bash
macadmin system-info --pretty
```

## `error: This script is intended for macOS`

You're running macadmin on Linux (likely in CI without `macos-latest`).
macadmin is macOS-only. Use the `macos-latest` runner in GitHub Actions.

## `kill: illegal pid`

The shell received a non-numeric `$PID`. This was a known bug in
`mac-scripts/scripts/system/kill-heavy-processes` and is fixed by
removing that script. If you migrated an older version, update.

## `install.sh` refuses `--dir` outside `$HOME`

By design. The installer never `rm -rf`s an arbitrary path. Install to a
subdirectory of `$HOME` instead:

```bash
./install.sh --dir "$HOME/work/macadmin"
```

## `make test` shows a mock error

The mock binary in `tests/mocks/` is not executable. `make test` does
`chmod +x tests/mocks/*` first, but if your `umask` is unusual, run it
manually:

```bash
chmod +x tests/mocks/*
```

## Tests pass locally but fail in CI

Most likely cause: macOS version mismatch. The CI runs on `macos-latest`,
which moves forward. Pin a specific version in
`.github/workflows/ci.yml` if you need reproducible behavior:

```yaml
runs-on: macos-14  # instead of macos-latest
```