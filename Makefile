.PHONY: help list lint format test

help:
	@echo "Targets: list lint format"

list:
	@echo "Scripts:" && ls -1 scripts | sed 's/^/ - /'

# Optional: requires shellcheck and shfmt installed locally
lint:
	@command -v shellcheck >/dev/null 2>&1 && shellcheck -S style -x scripts/*.zsh bin/macadmin lib/common.zsh || echo "shellcheck not installed; skipping"

format:
	@command -v shfmt >/dev/null 2>&1 && shfmt -w -ln posix -i 2 -ci -fn scripts bin lib || echo "shfmt not installed; skipping"

test:
	@echo "Running tests..."
	@chmod +x tests/mocks/* 2>/dev/null || true
	@zsh tests/run.zsh
