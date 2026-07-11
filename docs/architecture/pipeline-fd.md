# rush — compound-in-pipeline & fd-management: architecture options

Decision record from June 2026 (pre-7ag), kept as written for the historical analysis.
**Status: the "Option 2 (real fds)" decision at the bottom was superseded in practice** —
the shipped model is the incremental Ruby-IO one (Option 1). See the postscript at the
end for what actually happened and what would reopen the real-fd migration.

## The three coupled gaps

1. **Compound command as a pipeline stage** — `cmd | while read l; do …; done`,
   `{ echo a; } | cat`, `f | g` (function on either side), `cmd | if/for/case/( )`.
   Today these "parse" but the compound stage does nothing.
2. **Redirect targets aren't flushed/closed until process exit** — `{ echo x; } > f; cat f`
   in one invocation prints nothing (the file *is* written, only visible after rush
   exits). Affects simple redirects too. Forces our differential tests to divert to
   `/dev/null` or read files back via an input redirect.
3. **fd-duplication is unimplemented** — `2>&1`, `>&`, `<&`, `n>&m` are not in the
   grammar at all (`io_redirect` covers only `< > >> <> >|` + here-docs).

They are one decision because they all live in the **IO/fd model**.

## Current model (as built)

- `IoTable` = `{ fd => Ruby IO }` (StringIO in tests, real IO/File in prod). Immutable;
  `with(fd, io)` folds a new table. The shell's own streams are never mutated.
- `Redirection::FileRedirect#apply` = `io.with(fd, system.open_file(target, mode))` —
  opens a Ruby `File`, binds it. **Never closed or flushed.**
- `AST::Pipeline`: a single stage runs **in-process** (`executor.run`); a multi-stage
  pipeline → `PipelineRunner`, which **forks every stage** and runs each via
  `CommandRunner.new(executor, stage_node, stage_io).call`.
- `CommandRunner` assumes a **SimpleCommand** (`.words` / `.assignments` / `.redirects`).
  A compound/subshell/function node has no `.words` → `NoMethodError` inside the fork →
  the stage process dies with exit 1 and produces no output. **This is gap 1's root.**
- `External` spawns with `io.to_spawn_options` (Ruby `spawn` accepts IO objects) +
  `close_others: true`. So externals already inherit the right fds across a pipe.
- Forked stages / subshell / cmd-sub exit via `exit!` (a hard exit — **no buffer flush**).
  Simple pipelines work because the pipe write end is effectively flushed per write;
  the buffering seam is what bites compound bodies and file redirects.

## Option 1 — Stay in the Ruby-IO model, fix incrementally ("minimal")

- **Gap 1**: `PipelineRunner#run_stage` → `executor.with_io(stage_io) { executor.run(node) }`
  instead of `CommandRunner` — runs an arbitrary AST node per stage. Small, self-contained.
- **Gap 2**: redirections *own* the IO they open; flush+close it after the command (and
  before a forked stage's `exit!`). Removes the buffering footgun.
- **Gap 3**: add `>&`/`<&`/`n>&m` to the lexer+grammar + a `DupRedirect`. For **externals**
  reuse Ruby `spawn`'s fd-mapping (`to_spawn_options` can express `{2 => 1}` / `[:child,1]`);
  for **builtins** (in-process) alias fd 2 to the same IO object as fd 1.
- **Pros**: each piece is one differential-testable slice; keeps StringIO in-process
  testability (our meaningful-coverage + differential discipline survives); low risk per slice;
  reuses Ruby's spawn fd-mapping for the common (external) case.
- **Cons**: the in-process-vs-fork buffering seam remains the fragile spot; builtin-side
  `2>&1` via IO-aliasing is leaky (no shared kernel offset/append semantics); not bit-exact
  with a real shell in fd edge cases (seek, shared offset, `exec` fd surgery).

## Option 2 — Real file descriptors ("the correct model")

- `IoTable` = `{ fd => integer fd }`. `SystemCalls` gains `dup2`/`close`/`open`/`pipe`(→fds).
  Redirections `open()`→fd then `dup2` onto the target fd; pipelines `pipe()`→fds, each
  forked stage `dup2`s pipe ends onto 0/1 and closes the rest; externals inherit the fd
  table directly; builtins read/write via thin `IO.for_fd(n)` (sync) wrappers.
- **Pros**: matches real shells exactly — gaps 1/2/3 **and** `exec` fd manipulation all fall
  out; no buffering seam (real fds, sync writes); the right foundation for Phase 4 job
  control.
- **Cons**: **big rewrite** — `IoTable`, every builtin's stdout/stderr access, redirection
  classes, `External`, cmd-sub, subshell, the `SystemCalls` port **and the test fake**
  (it's StringIO-based; real fds break in-process assertions → need a tmpfile/pipe fake or
  accept less in-process coverage). Directly fights our "in-process coverage + differential"
  methodology; high risk; the suite is hard to keep green mid-migration.

## Option 3 — Hybrid: Ruby-IO in-process, fds only at the boundary

- Keep `IoTable` Ruby-IO-based for builtins/in-process (preserve StringIO testability), but
  add an explicit "fd intent" resolved to real fds **only at fork/spawn**. fd-dup is a
  symbolic entry (`[:dup, n]`) resolved at the boundary; redirect targets get
  ownership+flush/close; compound-in-pipeline via `with_io { run }` (same as Opt 1).
- **Pros**: keeps in-process testability + differential method; correct fd-dup where it
  matters most (externals); still incremental.
- **Cons**: two mental models; a pure in-process builtin chain with `2>&1` still needs the
  Opt-1 IO-aliasing — so it's "Opt 1 + boundary polish", not a clean split; complexity at
  the seam.

## Recommendation

**Do Option 1 (≈ Option 3 without pretending the seam is clean), as a slice sequence —
NOT the Option 2 rewrite now.** Option 2 is the right *eventual* model but fights this
project's in-process+differential testing discipline and is high-risk; defer it to Phase 4
(job control), when real fds are unavoidable anyway.

Proposed slices (each differential-testable, each one commit):

1. **compound-in-pipeline** — `PipelineRunner` runs an arbitrary AST node per stage
   (`with_io { run }`); a function/`{ }`/`( )`/`while`/`if`/`for`/`case` stage works.
   Headline win (`cmd | while read`). Watch the flush-before-`exit!` for builtin output;
   add a stage flush if a fork drops buffered writes.
2. **redirect flush/close** — redirections own opened IO; flush+close after the command and
   before a stage's `exit!`. Fixes `{ echo x; } > f; cat f` in one run; lets differential
   tests read written files directly instead of diverting to `/dev/null`.
3. **fd-duplication** — lexer+grammar for `>&`/`<&`/`n>&m`; a `DupRedirect` using spawn
   fd-mapping for externals + IO-aliasing for builtins. `2>&1` and friends. (Could split
   external-only vs builtin-aliasing into two slices.)

Order rationale: (1) is the most-requested behaviour and unblocks `cmd | while read`;
(2) removes the buffering footgun that currently distorts our tests; (3) is the most
contained but the lowest-frequency feature.

## Testing-methodology impact (the real constraint)

Our verification pressure is "as much meaningful in-process unit coverage as possible +
bit-exact differential vs dash." The historical shorthand was "100% coverage", but SimpleCov
cannot see every fork/exec path; coverage must not veto correct shell semantics. Option 2's
real fds run across processes (invisible to SimpleCov, hard to assert in-process), so it would
*erode* the method. Options 1/3 keep StringIO in-process and verify the fork/fd boundary
differentially — same as every slice 7x–7af. That alignment is the main reason to prefer 1/3
over 2 right now.

---

# DECISION (June 2026, historical): Option 2 (real fds). Migration plan.

> **History.** This section is preserved as recorded (commit `2ce1d42`, 2026-06-28).
> The M1–M5 plan below was never executed as written; the postscript after it is the
> current record.

## Test-fake strategy (the key choice)

Builtins run **in-process**, so they must write to a **capturable real fd**. Proposal:

- `SystemCalls` (the port) gains fd primitives: `pipe_fds → [r, w]`, `dup2(old, new)`,
  `close_fd(fd)`, `open_fd(path, mode) → fd`, and `io_for(fd)` (a cached
  `IO.new(fd, …, autoclose: false)` so a builtin can `.puts` to a real fd without owning it).
- **Prod fake = real fds**: fds 0/1/2 are the process's real std streams; redirects/pipes
  open real fds. Nothing simulated.
- **Test fake = real fds backed by Tempfiles**: the fake's std streams are tmpfile-backed
  fds (so output is real-fd-written yet capturable); `fake.captured(:stdout)` reads the
  tmpfile to assert. `dup2`/`open_fd`/`close_fd` use the *real* syscalls (we're testing the
  real mechanism, just with tmpfile-backed std streams instead of the terminal).

Net: builtin **logic stays in-process** (SimpleCov still sees it); fd behaviour (dup2,
close, inheritance) is exercised for real; the cross-process fork/exec paths stay `:nocov:`
and are pinned differentially vs dash — same discipline as before. Spec churn: builtin
output assertions move from `system.stdout.string` → `fake.captured(:stdout)`.

## Slice sequence

- **M1 — fd port + tmpfile-backed fake (foundation).** Add the port primitives above and the
  fake's tmpfile-backed std streams + `captured`. Migrate `IoTable` to hold **fd numbers**;
  `get(fd)` returns `system.io_for(os_fd)` so builtins are unchanged. Update `IoTable.standard`,
  `to_spawn_options` (logical→os fd map for `spawn`), `External`, and every builtin spec's
  output assertion. Biggest slice; no new user-facing behaviour, suite stays green.
- **M2 — redirect ownership: flush + close after the command.** Redirections track the fd
  they opened; close it when the command finishes (and before a forked stage's `exit!`).
  Fixes `{ echo x; } > f; cat f` in one run; lets differential tests read written files
  directly instead of `/dev/null`.
- **M3 — compound command as a pipeline stage.** `PipelineRunner` runs an arbitrary AST node
  per stage (`with_io { run }`); dup2 pipe fds onto 0/1 in the child. `cmd | while read`,
  `{ } | cat`, `f | g`, `cmd | if/for/case/( )`. (Independent of M1/M2 but cleaner on top
  of real fds.)
- **M4 — fd-duplication grammar + semantics.** Lexer/grammar for `>&`/`<&`/`n>&m`; a
  `DupRedirect` doing real `dup2`. `2>&1`, `1>&2`, `n<&m`, `>&word`. (Splittable: parse +
  externals first, then the in-process dup.)
- **M5 (later) — `exec` fd surgery** (`exec 3>file`, `exec 3>&-`) once the fd model is solid.

Each Mx is one differential-testable commit, suite green throughout.

---

# POSTSCRIPT (July 2026): what actually shipped — the incremental Ruby-IO path

The Option-2 decision above was superseded the same day it was recorded — in fact
Option 1's first slice (7ag) had already landed before the decision commit (`2ce1d42`,
07:14) was made; 7ah and 7ai followed it the same morning. All three implemented
**Option 1's slice sequence in the Ruby-IO model**, two of them (7ag, 7ai) still
carrying a "path 2" label in their commit messages (7ai's "Path-2 slice M3" even
mislabels the plan — fd-duplication is M4):

- **7ag** (`b88d8bc`) — compound command as a pipeline stage:
  `PipelineRunner#run_stage` → `executor.with_io(stage_io) { executor.run(node) }`.
  Exactly Option 1's slice 1; explicitly deferred the fd-number foundation.
- **7ah** (`91dc736`) — redirect targets flushed and closed after the command
  (`IoTable#close_opened_over`, object-identity diff; sync-mode redirect writes).
  Option 1's slice 2 — no M1 fd port underneath.
- **7ai** (`9c4b06e`) — fd-duplication (`2>&1`, `>&`, `<&`, `n>&m`, `n>&-`) via
  **IO-aliasing**: `DupRedirect` binds fd *n* to fd *m*'s Ruby IO object; externals get
  the right kernel fds because `Process.spawn` maps both logical fds to one real fd.
  Option 1's slice 3 — no `dup2` anywhere.

M1 — the "IoTable holds fd numbers + tmpfile-backed fake" foundation — **was never
built**. The journal ("Test-harness gotchas") records the call explicitly: the literal
rewrite was judged low-payoff because the fake `SystemCalls` stubs all fork/pipe/fd ops
and real-fd correctness is verified differentially against dash regardless. Everything
M2–M5 promised was then delivered *behaviorally* inside the Ruby-IO model: 7aj
(redirect-open failure → status 2), 7ak (`exec >file` / `exec 3>file` permanence — M5's
headline), 9e (`FdEntry` with borrowed/owned/closed states replacing the ClosedStream
sentinel), 9f (inherited-fd probing: absent fds fall back to a borrowed
`IO.for_fd(..., autoclose: false)` wrapper), 9i/9l/9n (dup-target validation, noclobber,
closing overwritten redirect streams). All differential-verified vs dash.

**Why it went this way**: the "Testing-methodology impact" section above was the real
constraint, and it won. Option 2 fights the in-process StringIO coverage discipline;
every gap turned out to be fixable one differential-testable slice at a time without the
big-bang IoTable migration, so the migration never earned its risk.

**Known symptoms of the compromise** (the residue Option 2 would dissolve):

- **The `T.untyped` concentration in `lib/rush/io_table.rb` / `lib/rush/fd_entry.rb`.**
  The stream slot has no precise type — entries hold whatever Ruby IO-ish object arrives
  (File, pipe end, StringIO in tests, `IO.for_fd` wrappers), so the Sorbet sigs say
  `T.untyped` (11 occurrences: 6 in io_table.rb, 5 in fd_entry.rb across the two files) and the RBS side papers over it
  with a structural `_IoStream` interface. A real-fd table would be `Integer`-keyed and
  fully typed.
- **The in-process `2>&1` aliasing leak** (Option 1's documented con): builtins alias
  Ruby IO objects instead of `dup2`-ing kernel fds, so shared-offset/append semantics
  are not bit-exact for in-process writers in fd edge cases (seek, shared offset).

**Reopening conditions.** Reopen the M1–M5 migration (the tmpfile-backed-fake strategy
above remains the key design) if any of these materialize: (a) a dash divergence pinned
by the differential corpus that traces to IO-aliasing rather than a local bug — i.e. the
aliasing leak becomes an observable `[stdout, exitstatus]` bug, not a theoretical one;
(b) a feature that requires kernel-fd semantics Ruby IO objects cannot express (e.g.
full `exec n>&m` surgery interacting with inherited-fd offsets); or (c) the typed-ledger
pressure makes the `io_table.rb`/`fd_entry.rb` untyped seam the last blocker to a gate
ratchet. Until then, the Ruby-IO model is the shipped, verified architecture — not a
temporary state.
