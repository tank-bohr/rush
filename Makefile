# Developer bootstrap: `make` (or `make install-hooks`) wires a commit-msg hook
# that verifies Conventional Commits with cocogitto (`cog`); the message format
# itself is documented in AGENTS.md. Merge and fixup!/squash! messages are
# exempt — merges into `live` are the release mechanism and must not be
# blocked. The hook is a real file target: it rebuilds when missing or when
# this Makefile — its recipe and content source — changes.

COG := cog
HOOKS_DIR := $(shell git rev-parse --git-path hooks)

.PHONY: install-hooks
install-hooks: $(HOOKS_DIR)/commit-msg

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
