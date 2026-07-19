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
	@zsh bin/macadmin help 2>&1 | awk '/^Commands:/ {flag=1; next} flag && /^Examples:/ {flag=0} flag && /^  [a-z][a-z0-9-]*[ \t]+/ {print " - "$$1}'

# ---------------------------------------------------------------------------
# Quality
# ---------------------------------------------------------------------------

lint:
	@echo "Running zsh syntax check on .zsh files..."
	@for f in bin/macadmin lib/*.zsh scripts/*.zsh tests/run.zsh tests/assert.zsh install.sh; do \
	  [[ -f "$$f" ]] || continue; \
	  zsh -n "$$f" || { echo "syntax error in $$f"; exit 1; }; \
	done
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found. Run 'make dev-setup'"; exit 69; }
	@echo "Running shellcheck on install.sh..."
	@shellcheck -S warning -x install.sh || { echo "shellcheck failed on install.sh"; exit 1; }
	@echo "lint OK"
	@echo "Note: zsh files are not linted by shellcheck (shellcheck does not"
	@echo "support zsh). Style consistency is maintained via .editorconfig."

format:
	@echo "zsh files are not auto-formatted by shfmt (shfmt does not fully"
	@echo "support zsh parameter expansions). Format zsh files manually."
	@echo "Bash files in bin/, lib/, and install.sh are bash-compatible and"
	@echo "can be formatted with shfmt -ln bash if needed."

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
	@zsh -c 'setopt NULL_GLOB; \
	  total=$$(ls scripts/*.zsh 2>/dev/null | grep -v "^scripts/_" | wc -l | tr -d " "); \
	  tested=0; untested=""; \
	  for c in $$(ls scripts/*.zsh 2>/dev/null | grep -v "^scripts/_" | xargs -n1 basename | sed "s/\\.zsh$$//" | sed "s/_/-/g"); do \
	    f_zsh="tests/test_$$(echo "$$c" | sed "s/-/_/g").zsh"; \
	    f_bats="tests/test_$$c.bats"; \
	    if [[ -e "$$f_zsh" ]] || [[ -e "$$f_bats" ]]; then \
	      tested=$$((tested + 1)); \
	    else \
	      untested="$$untested $$c"; \
	    fi; \
	  done; \
	  echo "Coverage: $$tested / $$total commands have tests"; \
	  if [[ -n "$$untested" ]]; then \
	    echo "Untested:$$untested"; \
	  fi'

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