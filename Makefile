# Developer bootstrap: `make` (or `make install-hooks`) wires two hooks. The
# commit-msg hook verifies Conventional Commits with cocogitto (`cog`); the
# message format itself is documented in AGENTS.md. Merge and fixup!/squash!
# messages are exempt — merges into `live` are the release mechanism and must
# not be blocked. The pre-commit hook runs actionlint whenever workflow files
# are staged — .github/workflows is the one part of the repo `rake` cannot
# lint. Each hook is a real file target: it rebuilds when missing or when
# this Makefile — its recipe and content source — changes.

COG := cog
ACTIONLINT := actionlint
HOOKS_DIR := $(shell git rev-parse --git-path hooks)

.PHONY: install-hooks
install-hooks: $(HOOKS_DIR)/commit-msg $(HOOKS_DIR)/pre-commit

$(HOOKS_DIR)/commit-msg: Makefile
	@command -v $(COG) >/dev/null || { echo 'install-hooks: cocogitto ($(COG)) not found in PATH' >&2; exit 1; }
	@mkdir -p $(dir $@)
	@printf '%s\n' \
		'#!/bin/sh' \
		'# Installed by `make install-hooks`; verifies Conventional Commits (see AGENTS.md).' \
		'command -v $(COG) >/dev/null || { echo "commit-msg: cocogitto ($(COG)) is not installed" >&2; exit 1; }' \
		'exec $(COG) verify --ignore-merge-commits --ignore-fixup-commits --file "$$1"' \
		> $@
	@chmod +x $@
	@echo 'installed $@'

# pre-commit is shared with beads, which manages its own marker-fenced section
# in the same file — so this recipe cannot overwrite wholesale like commit-msg
# does. Instead it strips and re-appends only its own fenced section, creating
# the file first if no other tool has yet.
$(HOOKS_DIR)/pre-commit: Makefile
	@command -v $(ACTIONLINT) >/dev/null || { echo 'install-hooks: $(ACTIONLINT) not found in PATH' >&2; exit 1; }
	@mkdir -p $(dir $@)
	@[ -f $@ ] || printf '%s\n' '#!/bin/sh' > $@
	@sed -i '/^# --- BEGIN RUSH ACTIONLINT ---/,/^# --- END RUSH ACTIONLINT ---/d' $@
	@printf '%s\n' \
		'# --- BEGIN RUSH ACTIONLINT ---' \
		'# Installed by `make install-hooks`; lints .github/workflows when staged.' \
		'git diff --cached --quiet -- .github/workflows || {' \
		'  command -v $(ACTIONLINT) >/dev/null || { echo "pre-commit: $(ACTIONLINT) is not installed" >&2; exit 1; }' \
		'  $(ACTIONLINT) || exit 1' \
		'}' \
		'# --- END RUSH ACTIONLINT ---' \
		>> $@
	@chmod +x $@
	@echo 'installed $@'
