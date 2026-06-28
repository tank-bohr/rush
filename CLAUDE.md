# Project Instructions for AI Agents

**rush** — a pure-Ruby POSIX `sh` (spec = POSIX.1-2017 §2). The oracle is **dash**: every
behaviour must be bit-exact with `dash -c`. Keep this file small and stable; bulk knowledge
lives in `docs/` and the backlog lives in beads (see "Where things live").

**Phases:** 0 scaffold ✓ · 1 MVP ✓ · 2 intermediate (in progress) · 3 full POSIX scripting ·
4 (optional) job control + interactive. Ruby 4.0.5 (asdf); dash at `/usr/bin/dash`.

## Build & Test

`bundle exec rake` must be **fully green** before any commit. It runs, in order:

1. **racc compile** — regenerate the parser from `grammar/shell.y`
2. **rubocop** — style + `Metrics/{MethodLength,ClassLength,ModuleLength,ParameterLists}`
3. **Sandi Metz metrics** — enforced via rubocop `Metrics/*` cops (the `sandi_meter` gem is
   broken on Ruby ≥ 3.2): class/module ≤100 lines, method ≤5 lines, ≤4 params, `AbcSize` ≤17
4. **rspec** — coverage floor **line 95 / branch 90** (`.simplecov`), kept near 100%
   voluntarily. Coverage is a regression signal, **not** an architecture constraint: don't
   contort designs to be in-process-testable — verify OS-boundary code (fork children, real-fd
   dup/close) **differentially vs dash** instead. `:nocov:` is available for irreducible OS
   wrappers but isn't required to hold the gate.

```bash
bundle exec rake             # the full green gate
exe/rush -c '<program>'      # run rush
dash  -c '<program>'         # the oracle to diff against
```

## Slice Workflow

Work proceeds in numbered **slices**. Each slice is **exactly one commit on `main`**:

- Commit message: `Phase N (Slice Xy): <summary>`, with a body explaining the change
  and how it was verified.
- End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- A slice lands only when `bundle exec rake` is green **and** the behaviour is verified
  **bit-exact vs dash** — the differential corpus in `spec/integration/differential_spec.rb`
  plus ad-hoc fuzzing. Differential comparison is on **`[stdout, exitstatus]`**;
  **stderr is ignored**.
- Stage files **explicitly** (`git add <paths>`) — never `git add -A` (avoids bundling
  stray/scratch files). Keep scratch fuzzers in the session scratchpad, not the repo.

## Commit & Push Policy

- **Commit** per slice as above.
- **Push ONLY when the user explicitly asks.** Do not push on session end, on
  "completion", or "to be safe". This **overrides** any beads guidance below that
  treats pushing as mandatory.

## Where things live

- **Backlog & forward tasks** → beads (`bd ready`, `bd show <id>`, `bd update <id> --claim`,
  `bd close <id>`). The single source of truth for what's next.
- **Per-slice lessons & POSIX-divergence findings** → `docs/journal.md`. Read it before
  starting related work.
- **Design / architecture decisions** → `docs/architecture/` (e.g. `pipeline-fd.md`).
- **Full per-slice detail** → `git log` (commit bodies are rich).

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
