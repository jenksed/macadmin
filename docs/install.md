# Install / Uninstall / Upgrade

## Install

```bash
git clone https://github.com/jenksed/macadmin.git
cd macadmin
make install
```

This runs `install.sh` with the default install directory (`~/.macadmin`).

`make install` does:

1. Copies the repo into `~/.macadmin` (configurable with `INSTALL_DIR=...`).
2. Initializes `~/.macadminrc` from `share/macadminrc.example` if absent.
3. Creates an empty `~/.macadminignore` if absent.
4. Symlinks `~/.macadmin/bin/macadmin` → `~/bin/macadmin`.
5. Appends a PATH marker to `~/.zshrc` (idempotent).
6. Verifies `macadmin help` and `macadmin system-info --json` work.

After install, restart your shell or `source ~/.zshrc`.

## Install to a custom directory

```bash
make install INSTALL_DIR="$HOME/work/macadmin"
```

`install.sh` rejects any `--dir` outside `$HOME`.

## Uninstall

```bash
make uninstall
```

This removes the `~/bin/macadmin` symlink and prints a warning about the
install directory. Delete `~/.macadmin` manually if you want a full removal:

```bash
rm -rf ~/.macadmin
```

## Upgrade

macadmin does not auto-update. To upgrade:

```bash
cd ~/.macadmin            # or wherever you installed it
git pull
make install              # re-applies the install
```

Or, if you keep a clone elsewhere:

```bash
cd /path/to/macadmin-clone
git pull
make install INSTALL_DIR="$HOME/.macadmin"
```

## Dependencies

Required:

- macOS (Darwin)
- zsh (preinstalled on macOS Catalina and later)

Optional but recommended:

- `jq` — for validating `--json` output
- `brew` — for the `brew-tools` command
- `sips` — preinstalled image tools
- `ffmpeg` / `HandBrakeCLI` — for `media optimize`
- `7z` — for `archive create --format 7z`

Install via `make dev-setup` for development tools (`shellcheck`, `shfmt`,
`bats-core`).

## Troubleshooting

See [troubleshooting.md](troubleshooting.md).