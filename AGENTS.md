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

`bundle exec rake` must be **fully green** before any commit. It first runs **racc
compile** to regenerate the parser from `grammar/shell.y`, then runs the independent gates
concurrently: **rubocop**, **reek**, **flay / flog**, **steep**, **sorbet**, and RSpec in up
to eight file shards. SimpleCov merges all shard results before enforcing coverage. Use
`RUSH_GATE_SERIAL=1 bundle exec rake` for the original deterministic serial/debug path, and
`RUSH_SPEC_SEED=<seed> bundle exec rake spec:parallel` to reproduce a parallel test run.

```bash
bundle exec rake                  # the fast parallel full green gate
RUSH_GATE_SERIAL=1 bundle exec rake # serial/debug fallback
bundle exec rake check_parser_drift # explicit generated-parser audit when needed
bundle exec rake benchmark        # opt-in startup/loop/expansion performance suite
bundle exec rake benchmark:check  # opt-in comparison with committed host baseline
bundle exec rake benchmark:allocations # five-sample allocation counts for interpreter workloads
bundle exec rake benchmark:profile # StackProf CPU/wall/object profiles; output stays under tmp/
RUSH_RUNTIME_TYPECHECKS=1 exe/rush -c '<program>' # opt into production Sorbet call checks
exe/rush -c '<program>'           # run rush (runtime call wrappers off by default)
dash  -c '<program>'              # the oracle to diff against
```

Coverage policy: aim for 100% meaningful line/branch coverage, but do not reject valid
shell features or contort the design just to satisfy SimpleCov. Fork/exec paths and other
irreducible process-boundary wrappers may be marked `:nocov:` and pinned by differential
behaviour tests instead; `.simplecov` thresholds are intentionally a guardrail, not the
project's definition of quality.

## Slice Workflow

Work proceeds in numbered **slices**. Each slice is **exactly one commit on `main`**:

- Commit message (Conventional Commits): `<type>: <summary> (Phase N, Slice Xy)`, with a
  body explaining the change and how it was verified. Types drive semver on `live`:
  `fix`/`perf` → patch, `feat` → minor, `!` after the type or a `BREAKING CHANGE:` footer
  → major; `ci`/`build`/`docs`/`refactor`/`test`/`chore` never release.
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

## Releases

`live` is the release branch; merging `main` into `live` is the act of releasing. On push
to `live`, semantic-release (`release.config.mjs`) computes the version from the
Conventional Commits, bumps `lib/rush/version.rb` + `Gemfile.lock`, writes `CHANGELOG.md`,
commits that back to `live` (`[skip ci]`) and creates the tag + GitHub Release using a
GitHub App token (events made with plain `GITHUB_TOKEN` cannot trigger workflows). That
Release fires `publish.yml`, which publishes the gem via RubyGems OIDC trusted publishing
with sigstore attestations — no stored API key. The version lines of those three files are
owned by the release bot on `live`; never bump them on `main`.

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
