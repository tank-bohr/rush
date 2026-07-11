# rush — Agent Instructions

Canonical project instructions for any AI agent working on **rush**. (`CLAUDE.md` is a thin
pointer to this file.)

**rush** — a pure-Ruby POSIX `sh`. The authority is the **POSIX.1-2017 §2** standard, to the
letter. **dash** is the practical oracle — the closest reference implementation — that we
verify against differentially, so rush matches `dash -c` in practice; but where dash itself
diverges from POSIX, follow the standard, not dash. Keep this file small and stable; bulk
knowledge lives in `docs/` and the backlog lives in beads (see "Where things live").

**Phases:** 0 scaffold ✓ · 1 MVP ✓ · 2 intermediate ✓ · 3 full POSIX scripting ✓ ·
4 interactive shell ✓ · 5 job control, terminal-free half ✓ · 6 job control, terminal
half ✓ (epic `rush-mv8`: set -m, process groups, tcsetpgrp handover, interactive default
-m, WUNTRACED/Stopped/^Z, fg/bg, pre-prompt notifications, jobs command text; the no-fork
EV_EXIT optimization stays parked as `rush-mv8.7`). Ruby 4.0.5 (asdf); dash at
`/usr/bin/dash`.

## Build & Test

`bundle exec rake` must be **fully green** before any commit. It runs, in order:

1. **racc compile** — regenerate the parser from `grammar/shell.y`
2. **rubocop** (style/static checks; config in `.rubocop.yml`)
3. **reek** (code-smell ratchet; config + rationale in `.reek.yml`)
4. **flay / flog** (structural-duplication and per-method complexity
   ratchets; thresholds in `tasks/complexity.rake`, baseline-pinned, only
   lowered)
5. **steep** (RBS type-check gate; config in `Steepfile`)
6. **sorbet** (inline `sig {}` type-check gate; config in `sorbet/config`)
7. **rspec** (+ SimpleCov coverage gate; 100% meaningful coverage is the target,
   not a design-at-any-cost rule)

```bash
bundle exec rake                  # the fast full green gate
bundle exec rake check_parser_drift # explicit generated-parser audit when needed
exe/rush -c '<program>'           # run rush
dash  -c '<program>'              # the oracle to diff against
```

Coverage policy: aim for 100% meaningful line/branch coverage, but do not reject valid
shell features or contort the design just to satisfy SimpleCov. Fork/exec paths and other
irreducible process-boundary wrappers may be marked `:nocov:` and pinned by differential
behaviour tests instead; `.simplecov` thresholds are intentionally a guardrail, not the
project's definition of quality.

## Slice Workflow

Work proceeds in numbered **slices**. Each slice is **exactly one commit on `main`**:

- Commit message: `Phase N (Slice Xy): <summary>`, with a body explaining the change
  and how it was verified.
- End every AI-authored commit message with a `Co-Authored-By:` trailer naming the
  actual model/agent that produced the slice; do not reuse another model's signature.
- A slice lands only when `bundle exec rake` is green **and** the behaviour is verified
  against the **dash** oracle — the differential corpus in `spec/integration/differential/`
  plus ad-hoc fuzzing — comparing **`[stdout, exitstatus]`** (stderr ignored). Where dash is
  known to diverge from POSIX, the standard wins and the divergence is noted in `docs/journal.md`.
- Stage files **explicitly** (`git add <paths>`) — never `git add -A` (avoids bundling
  stray/scratch files). Keep scratch fuzzers in the session scratchpad, not the repo.

## Commit & Push Policy

- **Commit** per slice as above.
- **Push ONLY when the user explicitly asks.** Do not push on session end, on "completion",
  or "to be safe". This **overrides** any beads guidance below that treats pushing as mandatory.

## Where things live

- **Backlog & forward tasks** → beads (`bd ready`, `bd show <id>`, `bd update <id> --claim`,
  `bd close <id>`). The single source of truth for what's next.
- **Per-slice lessons & POSIX-divergence findings** → `docs/journal.md`. Read it before
  starting related work.
- **Design / architecture decisions** → `docs/architecture/` (e.g. `pipeline-fd.md`).
- **Full per-slice detail** → `git log` (commit bodies are rich).

## Non-Interactive Shell Commands

Use non-interactive flags so a command never hangs on a prompt: `cp -f`, `mv -f`, `rm -f`
(`rm -rf` for dirs), `scp`/`ssh -o BatchMode=yes`, `apt-get -y`.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for task/backlog tracking. `bd prime` prints workflow context.

```bash
bd ready                # next available work
bd show <id>            # issue details
bd update <id> --claim  # claim work
bd close <id>           # complete work
```

**Scoped for this project:** beads holds the **backlog and forward tasks** only.
Narrative and lessons live in `docs/journal.md`; the record of *why* lives in `git log`
and the journal — do not treat `bd remember` as the sole knowledge store, and do not
delete `docs/`. **Pushing is never mandatory here — push only when the user asks**
(this overrides the default beads session-completion / mandatory-push workflow).
<!-- END BEADS INTEGRATION -->
