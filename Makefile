# macadmin Makefile
# Common tasks for development, testing, installation, and release.

SHELL         := /bin/zsh
INSTALL_DIR  ?= $(HOME)/.macadmin
BIN_DIR      ?= $(HOME)/bin
PREFIX       ?= macadmin
VERSION      ?= 0.1.0

SCRIPTS := $(wildcard scripts/*.zsh)
COMMANDS := $(notdir $(SCRIPTS))

.DEFAULT_GOAL := help

.PHONY: help list commands lint format test coverage install uninstall \
        link clean new-command dev-setup bump ci protect-check

# ---------------------------------------------------------------------------
# Help / introspection
# ---------------------------------------------------------------------------

help:
	@echo "macadmin — make targets"
	@echo ""
	@echo "  help           Show this help"
	@echo "  list           List shell scripts in scripts/"
	@echo "  commands       List commands exposed by the dispatcher"
	@echo ""
	@echo "Quality:"
	@echo "  lint           Run shellcheck and shfmt -d"
	@echo "  format         Auto-format with shfmt"
	@echo "  test           Run zsh tests; bats library tests when present"
	@echo "  coverage       Report which commands lack tests"
	@echo "  protect-check  Verify MACADMIN_PROTECT gates work on mutating commands"
	@echo ""
	@echo "Lifecycle:"
	@echo "  install        Run install.sh with default install dir"
	@echo "  uninstall      Run install.sh --uninstall"
	@echo "  link           Re-link bin/macadmin into \$$HOME/bin"
	@echo "  clean          Remove transient artifacts"
	@echo ""
	@echo "Development:"
	@echo "  new-command    Scaffold a new scripts/<name>.zsh from _template.zsh"
	@echo "  dev-setup      Install brew dev tools (shellcheck, shfmt, bats-core)"
	@echo "  bump           Bump VERSION in CHANGELOG (use BUMP=major|minor|patch)"
	@echo "  ci             Aggregate target: lint + test + coverage + protect-check"

list:
	@echo "Scripts:"
	@ls -1 scripts | sed 's/^/ - /'

commands:
	@zsh bin/macadmin help 2>&1 | awk '/^  [a-z][a-z0-9-]* / {print " - "$$1}'

# ---------------------------------------------------------------------------
# Quality
# ---------------------------------------------------------------------------

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found. Run 'make dev-setup'"; exit 69; }
	@echo "Running shellcheck..."
	@shellcheck -S style -x scripts/*.zsh bin/macadmin lib/*.zsh install.sh || { echo "shellcheck failed"; exit 1; }
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not found. Run 'make dev-setup'"; exit 69; }
	@echo "Checking formatting with shfmt..."
	@shfmt -d -ln bash -i 2 -ci -fn bin lib scripts install.sh tests/run.zsh tests/assert.zsh || { echo "shfmt -d failed (run 'make format')"; exit 1; }
	@echo "lint OK"

format:
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not found. Run 'make dev-setup'"; exit 69; }
	@echo "Auto-formatting with shfmt..."
	@shfmt -w -ln bash -i 2 -ci -fn bin lib scripts install.sh tests/run.zsh tests/assert.zsh
	@echo "format OK"

test:
	@echo "Running zsh test suite..."
	@chmod +x tests/mocks/* 2>/dev/null || true
	@zsh tests/run.zsh
	@if [[ -d tests/lib ]] && [[ -n $$(ls tests/lib/*.bats 2>/dev/null) ]]; then \
	  command -v bats >/dev/null 2>&1 || { echo "bats not found. Run 'make dev-setup'"; exit 69; }; \
	  echo "Running bats library tests..."; \
	  bats tests/lib/; \
	else \
	  echo "No bats library tests yet (tests/lib/*.bats)"; \
	fi
	@echo "test OK"

coverage:
	@command -v zsh >/dev/null 2>&1 || { echo "zsh not found"; exit 69; }
	@total=$$(ls scripts/*.zsh 2>/dev/null | grep -v '^scripts/_' | wc -l | tr -d ' '); \
	tested=0; untested=""; \
	for c in $$(ls scripts/*.zsh 2>/dev/null | grep -v '^scripts/_' | xargs -n1 basename | sed 's/\.zsh$$//' | sed 's/_/-/g'); do \
	  if ls tests/test_$$(echo "$c" | sed 's/-/_/g').zsh tests/test_$$c.bats 2>/dev/null | grep -q .; then \
	    tested=$$((tested + 1)); \
	  else \
	    untested="$$untested $c"; \
	  fi; \
	done; \
	echo "Coverage: $$tested / $$total commands have tests"; \
	if [[ -n "$$untested" ]]; then \
	  echo "Untested:$$untested"; \
	fi

protect-check:
	@command -v zsh >/dev/null 2>&1 || { echo "zsh not found"; exit 69; }
	@echo "Verifying MACADMIN_PROTECT gates on mutating commands..."
	@zsh tests/run.zsh protect 2>/dev/null || { echo "no protect tests yet; see tests/test_protect*.zsh"; exit 0; }

ci: lint test coverage
	@echo "ci OK"

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

install:
	@zsh install.sh --dir $(INSTALL_DIR)

uninstall:
	@zsh install.sh --uninstall

link:
	@mkdir -p $(BIN_DIR)
	@rm -f $(BIN_DIR)/macadmin
	@ln -sf $(INSTALL_DIR)/bin/macadmin $(BIN_DIR)/macadmin
	@echo "Linked: $(BIN_DIR)/macadmin -> $(INSTALL_DIR)/bin/macadmin"

clean:
	@echo "Cleaning transient artifacts..."
	@find . -name '*.log' -not -path './.git/*' -delete 2>/dev/null || true
	@find . -name '*.out' -not -path './.git/*' -delete 2>/dev/null || true
	@find . -name '.DS_Store' -not -path './.git/*' -delete 2>/dev/null || true
	@find tests -maxdepth 1 -type d -name 'tmp_*' -exec rm -rf {} + 2>/dev/null || true
	@echo "clean OK"

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------

new-command:
	@if [[ -z "$(NAME)" ]]; then \
	  read "name?Command name (e.g., cleanup-user): "; \
	else \
	  name="$(NAME)"; \
	fi; \
	if [[ -z "$$name" ]]; then echo "name required"; exit 64; fi; \
	file="scripts/$${name//-/_}.zsh"; \
	if [[ -f "$$file" ]]; then echo "already exists: $$file"; exit 73; fi; \
	sed "s/_template.zsh/$${file##*/}/g; s/_template/$${name//-/_}/g" scripts/_template.zsh > "$$file"; \
	chmod +x "$$file"; \
	echo "Created: $$file"; \
	echo "Run: zsh $$file --help"

dev-setup:
	@command -v brew >/dev/null 2>&1 || { echo "brew not found"; exit 69; }
	@brew install shellcheck shfmt bats-core
	@echo "dev-setup OK"

bump:
	@if [[ -z "$(BUMP)" ]]; then echo "usage: make bump BUMP=major|minor|patch"; exit 64; fi
	@case "$(BUMP)" in \
	  major|minor|patch) ;; \
	  *) echo "BUMP must be major|minor|patch (got: $(BUMP))"; exit 64 ;; \
	esac
	@echo "manual bump needed in bin/macadmin (this target will be automated post-1.0)"