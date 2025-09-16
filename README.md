# Mac Admin Zsh Scripts

Zsh-based library of scripts to manage macOS systems. Includes a simple dispatcher, common helpers, and focused utilities for updates, cleanup, settings, networking, backups, and hardening.

## Quick Start

- Run any script directly, e.g.: `zsh scripts/system_info.zsh`
- Or use the dispatcher: `zsh bin/macadmin <command> [args]`

## Commands

- `system-info`: Summarize OS, hardware, disks, network.
- `os-update`: List/install macOS updates via `softwareupdate`.
- `cleanup`: Clear caches, rotate logs, run periodic tasks.
- `settings-ui`: Apply sensible Finder/Dock/Text settings.
- `network`: Wi‑Fi on/off, list services, flush DNS.
- `brew-tools`: Check/ensure Homebrew, run `brew bundle`.
- `backup-tmutil`: Time Machine helpers (start, list, thin, exclude).
- `hardening`: Enable firewall, Gatekeeper; show security status.

## Dispatcher Usage

```
zsh bin/macadmin help
zsh bin/macadmin system-info
zsh bin/macadmin os-update --list
zsh bin/macadmin cleanup --user --dry-run
```

## Conventions

- All scripts are `zsh` with `setopt errexit nounset pipefail`.
- `DRY_RUN=1` prints actions without executing where applicable.
- `require_sudo` prompts once when a script needs elevated privileges.

## Notes

- Some commands require admin rights (e.g., system caches, DNS flush, updates).
- Homebrew installation requires network access and user confirmation.

# macadmin
