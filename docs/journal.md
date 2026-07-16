# rush — engineering journal

Durable lessons and cross-cutting findings from building rush, a pure-Ruby POSIX `sh`
whose oracle is **dash**. This is the lab notebook, not the backlog:

- **What's next / open bugs** → beads (`bd ready`). Not here.
- **Per-slice blow-by-blow** → `git log` (commit bodies are detailed).
- **Design decisions** → `docs/architecture/`.
- **This file** → the *why* and the non-obvious gotchas worth not re-learning.

Verification model for every behavioural claim below: differential against the **dash**
oracle — the closest POSIX reference, but the **standard wins where dash diverges** —
comparing **`[stdout, exitstatus]`** (stderr ignored), via the differential corpus
(`spec/integration/differential/`) plus ad-hoc randomized fuzzing.

---

## Charter — what rush is actually investigating

rush is a **research project about Ruby (the language + ecosystem), not about shells**: a
POSIX `sh` is a deliberately *solved* problem (dash is the oracle, correctness is externally
decidable), so all effort goes to the *how* — under extreme quality pressure (RuboCop +
Sandi-Metz + reek + meaningful coverage pressure + mutant + two type systems), what does the
ecosystem offer for non-trivial code, and what code results? Coverage aims at 100% where it is
meaningful, but shell semantics cross process boundaries that SimpleCov cannot observe; the
metric serves the design, not the reverse. Two type systems (RBS/Steep and inline Sorbet) are run
independently on the same code — the task is to compare how each fares. The standalone result is
[Two type systems, one Ruby interpreter](steep-vs-sorbet.md); the chronological raw evidence remains
below.

---

## POSIX divergences discovered (and where they went)

Found while building; each was out of scope when found, then fixed in a later slice or
filed as a beads issue.

1. **Backticks inside double quotes** left literal — **fixed (7s):** `DOUBLE_LITERAL`
   excludes backtick; `double_step` runs it as a quoted command substitution.
2. **No redirects on compound commands** — **fixed (7t):** grammar
   `command : compound_command redirect_list`; `AST::Redirected` + `Executor#run_redirected`.
3. **Bare-assignment exit status from command substitution** — **fixed (7u):** `x=$(false)`→1.
   Executor cmd-sub channel; `run_bare` returns `cmd_sub_status`; kept OFF `last_status` so a
   later `$?` in the *same* command still sees the previous command's status, as dash does.
4. **`return`/`exit` wide codes** (>255 kept in `$?` in-process) — **fixed (7af):** dropped the
   `% 256` clamp in `Status`; the wrap to 0–255 still happens at the real process boundary
   (Ruby `exit`, and `exit!` for subshell/pipeline/cmd-sub).
5. **`return`/`exit`/`break`/`continue` argument validation** — **fixed (7ab/7ae):** an invalid
   operand is a special-builtin error → abort non-interactive shell with 2 (fires EXIT trap).
   Accepted form `/\A\s*\+?\d+\s*\z/` AND value ≤ `INT_MAX` (2147483647) — the boundary is
   **INT_MAX, not LONG_MAX** (dash parses into a C `int`). `break`/`continue` minimum is 1 and
   is validated even with no enclosing loop.
6. **eval/`.` syntax error should abort** the shell with 2 — **fixed (7ac):** they `raise
   BuiltinError`; complete commands before the error still run+flush, then the shell aborts.
   dot's missing-OPERAND usage error does NOT abort (pinned), unlike a missing FILE.
7. **Top-level `return` acts like `exit N`** — **fixed (7z).**
8. **`break`/`continue` set `$?`=0** (successful special builtins) — **fixed (7y).**
9. **`break N`/`continue N` lexical loop scoping** — **fixed (7aa):** see the loop-scoping
   lesson below.
10. **Bare `exit` in the EXIT trap** uses the terminating status, not the trap body's `$?`
    — **fixed (7ad).**
11. **Redirect-open failure** crashed rush with an uncaught `Errno` — **fixed (7aj):** see the
    redirect lesson below.
12. **`exec` redirect-only permanence** (`exec >file` / `3>file` closed out from under the shell)
    — **fixed (7ak):** see the exec lesson below.
13. **Function-call redirects not applied to the body** (`f >file` printed to stdout) — **fixed
    (7al):** see the function-redirect lesson below.
14. **`shift` past `$#` (and a bad operand) didn't abort** (rush no-op'd with status 1) — **fixed
    (7am):** now a special-builtin `BuiltinError`. See the shift lesson below.
15. **Missing `hash` / `times` builtins and `set -v`** — **added (7an):** the low-value trio. See
    the trio lesson below; includes one accepted `hash` auto-cache divergence.
16. **A fatal error inside the EXIT trap re-entered it and escaped as a Ruby backtrace** — **fixed
    (17b):** EXIT is claimed once before evaluation; syntax/expansion/readonly/special-builtin
    failures report once and terminate with 2, while explicit `exit` retains its override semantics.
17. **Caught signal traps re-entered the parser/executor from Ruby's `Signal.trap` callback** —
    **fixed (17c):** callbacks only coalesce pending signal names; explicit evaluator, EXIT, and
    PS1 checkpoints deliver shell actions after the interrupted command publishes its status.

**Notes:**
- **`pwd` / `$PWD`**: a fuzz "divergence" where rush printed an inherited `$PWD` vs dash's
  `getcwd` was a **harness artifact** (Open3 `chdir` without updating `$PWD`), not a real bug —
  noted so it isn't re-chased.

---

## Key implementation lessons

### errexit (`set -e`) — the "tested" flag (7c)
A dynamically-scoped `@tested` flag on `Executor` mirrors dash's `EV_TESTED`. The leaf check
(`exit_on_error`) aborts only when errexit is on, the status failed, and we're **not** in a
tested context. Tested contexts: if/while/until conditions, the non-final part of `&&`/`||`,
a negated `!` pipeline, an async `&`. Command substitution starts a **fresh untested** context
and catches `ExitSignal` so a `set -e` failure ends only the sub-shell.

### Special-builtin fatal-error mechanism — `BuiltinError` (7ab → reused widely)
`Rush::BuiltinError` is the lever for POSIX 2.8.1 "a special-builtin error aborts a
non-interactive shell with 2." Routing: `CLI#run_source` rescues it → abort 2 + fire EXIT trap;
the **REPL reports and stays alive** (interactive ≠ abort); `SubshellRunner#report_fatal` → 2 so
the error aborts only the subshell, parent continues. Now used by exit/return/break/continue arg
validation, eval/dot syntax errors, and (7aj) redirect failures on special builtins.

### Caught traps are queued; shell code runs only at safe checkpoints (17c)
Ruby runs `Signal.trap` blocks on its main VM thread, but that does **not** make parser/executor
re-entry safe: dash finishes a foreground utility before evaluating its trap (`S`, then `T`),
where rush used to run the action inside the callback (`T`, then `S`). The callback now performs
only one hash write into `PendingSignals`; the evaluator drains after publishing a node's status,
before EXIT teardown, and before PS1. Subshell entry clears the copied queue. Batch transfer swaps
in a fresh hash **before** sorting/delivery rather than snapshot-then-clearing the live hash: a
callback may run between any two Ruby operations, and clearing would erase a signal recorded in
that window. A detached batch also prevents already-pending USR2 from jumping ahead through the
USR1 action's own entry checkpoint; distinct signals therefore drain by signal number (`USR1`,
then `USR2`), while signals newly raised *inside* an action remain eligible at its next command
boundary. dash permits that nested delivery, including same-signal `A A B B D`; no “trap active”
guard is correct.

Status timing is part of the boundary. A foreground child that exits 5 gives the trap `$?=5` and
the following command still sees 5. Pending traps drain before EXIT (`S T E`) and checkpoints
remain live inside EXIT (`E1 T E2`). Ruby restarts blocking `waitpid2` and `IO#gets` after a
record-only handler, so only the `wait` and `read` builtins need interruptible polling: foreground
await stays blocking, `wait` polls the requested pid with WNOHANG and returns `128+signal` without
forgetting the child's eventual/remembered status, while IO-backed `read` consumes one
nonblocking byte per readability poll (so a partial, unterminated line stays interruptible) and
returns 1. With no bytes it assigns nothing; if bytes were consumed first, dash assigns that
partial field while leaving input written by the trap for the next read. `JobTable` remains the
sole reaper. The differential cases avoid
timing sleeps: helper children wait until `ps` observes the shell blocked, and FIFOs keep the
post-signal child/input alive; repeated runs pin first-wait interruption followed by the real
status, and read interruption followed by consumption of the untouched line.

### Runtime errors are classified once, handled at their existing boundaries (17d)
The same four operational failures (parse, expansion, readonly and special-builtin) had been
spelled independently in batch, REPL, `command`, ordinary-trap and EXIT-trap rescue lists, while
a subshell caught the entire `Rush::Error` hierarchy and guessed from a `case`. That made a new
error silently fatal in children but uncaught elsewhere. `ErrorPolicy` is now an exact-class,
six-context matrix: batch, interactive, subshell, command demotion, signal trap and EXIT trap.
Its decisions are semantic (`abort2`, `recover2`, `return_code`, `preserve_code`, `propagate`,
etc.), while reporting, fd choice, status publication and the one-shot EXIT lifecycle stay at
the owning boundary. Exact lookup is deliberate: a new named `Rush::Error` must gain an explicit
row, and the table spec compares the matrix against every named subclass.

The asymmetries are the design, not duplication to erase. `BuiltinError` aborts batch/EXIT,
recovers in the REPL, demotes under `command`, but propagates from an ordinary signal trap;
`ReturnSignal` terminates batch through Source's existing conversion, is ignored by the REPL,
returns a code from a subshell, and preserves the incoming EXIT status; loop control preserves a
subshell/EXIT status; redirect, job, test and invocation errors retain their narrower owners.
No inheritance-only catch-all decides policy, and control-flow rows are asserted not to acquire a
diagnostic demotion accidentally.

### Command modes share metadata, not one search algorithm (17e)
Ordinary execution, `type`/`command -v`, and execution-form `command` look related but have
intentionally different POSIX orderings. Direct execution resolves special builtin → function →
regular builtin → external; lookup additionally considers keywords and aliases and reports a
function before builtin metadata; `command` bypasses functions, while `-p` changes only its
external path. One universal resolver would silently flatten those distinctions.

`CommandResolution` therefore owns only the shared special-builtin catalog and the typed direct-
execution result: kind, assignment lifetime, and redirect-failure policy. `CommandRunner` still
owns expansion, redirect timing, assignment application, external construction, and the
load-bearing function-redirect lifetime check. Special classification requires both catalog
membership and a registered implementation in execution *and* lookup; this closes the old drift
where an unavailable catalog name was reported by `type` as an implemented special builtin even
though execution fell through. Direct special prefixes persist and redirect setup failures are
fatal; functions/regular builtins use temporary prefixes; externals receive only an environment
overlay. A special target reached through the regular `command` builtin inherits the outer
command's temporary-assignment/nonfatal-redirect policy, not direct-special policy.

### Forked modes share entry, not a lifecycle (17f)
The explicit subshell, each pipeline stage, an async list and command substitution all call
`Executor#enter_subshell`, but the order around that call is load-bearing and intentionally
asymmetric. A stage closes unused pipes, arms its stop relay and binds stage IO before entry;
background snapshots monitor before entry, then installs unmonitored INT/QUIT ignores and
`/dev/null` stdin after inherited base handlers have dropped; command substitution binds stdout
before entry and alone forces a fresh untested errexit context. Parent completion differs just as
much: foreground job wait, no wait, or pipe-read-before-wait.

The background path's second entry through `SubshellRunner` is harmless only because isolation
creates no reset-sensitive shell state between calls: no body, child job, pending signal, caught
trap or EXIT action. Raw dispositions and stdin are deliberately installed there, and the second
entry does not reset them. Entry is not generally idempotent: it replaces EXIT state and clears
pending signals. The characterization matrix and ordered tests now make that
conditional guarantee explicit; any extraction must expose ordered phases rather than merge the
modes behind flags. See `docs/architecture/forked-execution-modes.md`.

### Mutation ownership stays with the aggregates, but every write gets a name (17g)
`Executor` is the interpreter environment and `ShellState` the POSIX state aggregate; splitting
registries or session tables out merely to lower a metric would replace useful direct collaborator
APIs with facades. The safer boundary is writer ownership. Ordinary options pass through
`ShellState#set_option` so `allexport` and `ShellVariables` cannot drift. Live `monitor` is the one
exception: `JobControl` owns the option together with its signal/tty/process-group effects; an
invocation may only seed the pre-executor flag, which `#startup` replays through that policy.

The remaining scalar writes were already narrow and are now contractual: `ShellState` publishes
`$?`/`$!` only through its record/scoped methods, while `Executor` owns scoped versus durable base IO
and its separate command-substitution status channel. `JobTable` remains the job/reap/control-state
owner and `JobControl` remains stateless. Visibility specs pin the absence of raw scalar writers;
existing behavioural specs pin allexport mirroring, monitor side effects, status publication,
background pid publication and IO restoration without source-scanning the implementation.

### Simple commands are born in source order instead of repaired afterward (17h)
`SimpleCommand.from_parts` used to partition the parser's ordered array through the grouped
constructor, then mutate `#parts` back into source order with `tap`/`replace`. That made the
canonical representation true only after construction and let grouped test setup masquerade as
the ordinary initializer. `SimpleCommand.new(parts)` now receives and stores the parser's final
source-order array directly; source-line derivation and grouped execution views remain derived
from that one representation.

Tests that intentionally start from assignments/words/redirects use the explicitly artificial
`from_groups` factory. No wrapper object or execution rewrite rides along: concrete part classes
remain the tag, `CommandRunner` keeps its grouped views, and the parser grammar is unchanged.

### Incremental execution — `ProgramReader` / `SourceRunner` (7v, 7x)
The CLI and REPL both pump source **one line at a time** through `ProgramReader`, accumulating
until a complete program parses (`IncompleteInput` → read another line). Consequences that match
dash: a syntax error mid-script runs+flushes prior complete commands first, then aborts 2; a
blank/comment-only line is its own empty program and **preserves `$?`**. `eval`/`.` use the same
`SourceRunner`, so an alias/function defined on one line shapes the parsing of that construct's
own later lines.

### alias — lex-time splice (7w)
Alias substitution is **lex-time**: `Lexer::AliasExpander` re-points the scanner at the alias
value (`splice`) and an input-frame stack drains exhausted frames. Eligibility = command
position OR a trailing-blank carry (`@check_next`, set at frame-pop when a value ends in blank,
spent on the next emitted token) — this is what makes a blank-ending alias expand the *following*
word. Reserved words outrank aliases (classify first). `LexState#command_mode?` gates it so case
subjects/patterns and for-headers are never expanded.

### break/continue lexical loop scoping (7aa) — functions reset, subshells inherit
`ShellState` carries a loop-depth counter. A **function body resets** it (lexically separate);
**dot/eval/group bodies keep** it. The asymmetry the *design got wrong and the fuzz caught*: a
**subshell `( )` INHERITS** the depth — it's lexically inside the loop, so a `break` there
unwinds to the subshell boundary and ends the subshell, leaving the parent loop (a separate
process) untouched. A stray break/continue with no enclosing loop is a no-op; a level past the
nesting is clamped.

### fd / IO model (path 2 — real fds) (7ag–7ai)
- **Binding fd *n* to fd *m*'s IO object IS the dup.** `2>&1` / `>&` / `<&` just point fd n at
  m's stream (`io.with(n, io.get(m))`). No real `dup2` syscall: `Process.spawn` inherits the
  IoTable so both logical fds map to one real fd; builtins share the IO object. The left-to-right
  fold of redirects (`with_redirects`' reduce) gives correct ordering (`>f 2>&1` → both to f;
  `2>&1 >f` → stderr to old stdout).
- **`n>&-` closes** fd n → a closed `FdEntry` whose stream access raises `Errno::EBADF` (a write
  fails the command with status 1, caught in `CommandRunner#builtin`; the shell continues) and
  which `IoTable#to_spawn_options` maps to `:close`. Dup *from* a closed/unopened fd →
  `RedirectError` (status 2, shell continues); a **non-numeric** dup target → `BuiltinError`
  (fatal).
- **Flush/close after the command** (`close_opened_over`): an owned redirect target is closed when
  the command finishes, identified by object-identity diff `io.entries - base.entries`, so borrowed
  stdio, inherited streams and pipe ends are untouched. Redirect files are opened in **sync mode** so
  a forked subshell's output survives its `exit!` (which flushes only the std streams).
- **Inherited fd probing** (9f): dup redirects first consult `IoTable`; if the source fd is absent,
  `SystemCalls#inherited_fd` lazily wraps the real process fd with `IO.for_fd(..., autoclose: false)`
  and binds it as a borrowed `FdEntry`. A logically closed entry still wins over the real fd, so
  `9>&-; 1>&9` fails even if the OS fd 9 exists, and borrowed inherited fds are never closed by
  per-command redirect cleanup.
- **Compound command as a pipeline stage** (7ag): `PipelineRunner#run_stage` runs the arbitrary
  AST node with stdin/stdout bound to the pipe (`with_io(stage_io) { run(node) }`), so
  `cmd | while read`, `{ } | cat`, `( ) | cat`, `f | g` work.

### Redirect-open failure (7aj)
A target that can't be opened (missing dir, EACCES, EISDIR) is a **redirection error**, not a
crash. `FileRedirect#apply` rescues `SystemCallError` → `RedirectError`. **All** redirect
failures are status 2 in dash. Regular command / function / regular builtin / no-command-word →
status 2, shell continues (`Executor#run` maps `RedirectError`→2). **Special builtin** →
`CommandRunner#run_command` re-raises as `BuiltinError` → fatal abort 2 + EXIT trap.

### `exec` redirect-only permanence — the last path-2 piece (7ak, beads `rush-6wx.1`)
`exec >file` / `exec 3>file` must persist for the rest of the shell. The committal was already
wired via `executor.replace_io(@io)`; the dup form (`exec 2>&1`) already worked because it opens
no new stream (`ios - base.ios` is empty, so `close_opened_over` closes nothing). The bug was
that `with_redirects`' `ensure` then **closed the file opened over base, undoing the committal** —
the next command wrote to a closed stream. Fix: skip the close when the executor committed the io,
i.e. `io&.close_opened_over(base, system) unless io.equal?(@io)`. After `replace_io(io)` the
executor's `@io` *is* the yielded table, so identity tells "exec kept this" from "scope it".
Why the obvious alternatives don't regress: a per-command redirect yields a *derived* table
(`base.with(...)`) that is never installed as `@io`, so it still closes; `run_redirected`/pipeline
stages set `@io` only inside a nested `with_io` whose `ensure` restores `@io` *before* this one
runs, so identity is false there too; a no-redirect call yields `base` itself (`== @io`) and skips,
but `close_opened_over` would have been a no-op anyway. A forked subshell's `exec >f` mutates only
the child's `@io` and dies, so it can't leak (verified differentially: `( exec >sub; … ); echo
outside`). Restoring the real stdout for read-back in the corpus uses a spare fd (`exec 4>&1; exec
>f; …; exec 1>&4 4>&-; cat f`) rather than `exec 1>&-`, which would just feed `cat` a closed fd1.

### Function-call redirects bind the body — but only as a *scope* (7al, beads `rush-6wx.2`)
A function runs in the current shell (not a subshell), so a redirect on the *call* (`f >file`)
must bind the whole body — `CommandRunner#dispatch` was passing the redirected `io` to builtins
and externals but `run_function` ignored it, so the body printed to the shell's stdout. The fix
is *not* an unconditional `with_io(io)` wrap, because two dash behaviours pull opposite ways and
both must hold (confirmed differentially):
- `exec >x` inside a call with **no** redirect **persists** (the body shares the shell io table).
- `exec >x` inside `f >file` is **undone** when `f` returns (the call's redirect is a scope torn
  down on return — dash restores the fd saved at `>file`, discarding the inner exec too).
So wrap in `with_io` **only when a redirect actually layered a new table**, detected by identity:
`io.equal?(@executor.io) ? run.call : @executor.with_io(io, &run)`. No redirect → `io` *is* the
base → run in place so an inner `exec` mutates `@io` permanently; redirect present → wrap, and
`with_io`'s unconditional restore correctly tears the scope (inner exec included) down on return.
This mirrors `run_redirected`, which already wraps compound bodies and is only reached when
redirects exist. The ambiguity trap while probing: assert the *destination*, not just combined
stdout — `f(){ exec >g; }; f; echo X` yields the same stdout whether exec persisted or not; only
splitting "before vs after restore" output across distinct files tells them apart.

### `shift` is a special builtin — its errors abort (7am, beads `rush-6wx.3`)
`shift n` with `n > $#` ("can't shift that many") and a bad operand ("Illegal number") are both
special-builtin errors: a non-interactive shell aborts with 2 and fires the EXIT trap. rush used
to no-op with status 1. Fix: `raise BuiltinError` for both — it propagates past `Executor#run`
(which only rescues `RedirectError`) to `CLI#run_source`, which prints, publishes `$?`=2 and runs
the EXIT trap; in the REPL `repl.rb` rescues it instead, so interactive shells don't die (as dash).
The operand validation is exactly `Base#numeric_operand` (`/\A\s*\+?\d+\s*\z/`, min 0): probing
dash showed `number()` accepts a leading `+`, leading zeros (decimal, not octal) and surrounding
blanks (`+1`/`01`/` 1` all shift 1) but rejects trailing garbage / empty / hex (`1abc`/``/`0x2`),
and **ignores operands past the first** (`shift 1 2` ≡ `shift 1`) — so no bespoke parser is
needed. `shift 0` and `shift $#` (exactly) succeed; only `> $#` aborts.

### The low-value trio: `hash` / `times` / `set -v` (7an, beads `rush-6wx.4`)
"Low-value" because none is cleanly differential-testable; verified by format/structure plus
unit specs, with a few deterministic differential cases.
- **`times`** — two lines, `<min>m<sec>s <min>m<sec>s` (shell, then children), six-decimal
  seconds, via a `SystemCalls#times` port (`Process.times`; the fake returns zeros). The values
  are non-deterministic so there is no differential case — a unit spec pins the format.
- **`set -v`** — added `v`/`verbose` to the option maps; the echo lives in `CLI#run_commands`,
  which wraps the line-pump so each input line is written to stderr *as it is read* when verbose
  is set. Because the flag is checked at read time and lines are pulled lazily by `ProgramReader`,
  a `set -v`/`set +v` correctly toggles which *later* lines echo. In `-c` mode the whole program
  is one "line" already read, so nothing echoes — matching dash. (stderr, so differential-blind.)
- **`hash`** — an explicit `command_hash` (name→path) on `ShellState`: `hash name` resolves via
  `CommandLookup#find` and caches a `:file` hit (a slash path / builtin / function is a no-op; an
  unknown name errors with status 1, but `hash` is a *regular* builtin so it does not abort); `-r`
  clears; bare `hash` lists paths sorted by name. **Accepted divergence:** rush does not
  auto-populate the cache as commands execute (dash caches a utility's location on use), because
  rush delegates PATH resolution to `Process.spawn` (the OS) and has no resolved path to record
  without a redundant lookup on the hot path. Observable only via `<cmd>; hash`; the cache is
  otherwise bit-for-bit consistent with dash (`hash a z; hash` lists `a` then `z` by full path).
- Naming: the builtin class is `Rush::Builtins::Hash`, shadowing `::Hash` only within the
  `Builtins` namespace (the `Set` builtin sets the precedent) — chosen over `Hash_` so the spec
  path cop is satisfied; safe because no builtin references core `Hash`.

---

## Test-harness gotchas

- **The fake `SystemCalls` STUBS all fork/pipe/fd ops** (`fork`→nil, `pipe`→disconnected
  StringIOs, `exit!`→flush+record, `open_file`→StringIO). So multi-process IO is verified
  **differentially**, and in-process specs cover builtin logic on StringIO. This is why the
  literal "IoTable holds bare fd-numbers" rewrite was low-payoff and was skipped — real-fd
  correctness lives in prod + differential regardless.
- **Coverage is a design pressure, not the product.** We still target 100% meaningful coverage,
  and the suite currently reaches it, but `.simplecov` intentionally keeps relaxed thresholds
  because SimpleCov cannot see forked/exec'd code paths. Use `:nocov:` for irreducible process
  wrappers, then pin the real behaviour with subprocess/differential tests instead of deleting
  shell features or distorting boundaries to satisfy a metric.
- **Differential harness + asdf:** invoke rush via the absolute `RbConfig.ruby` (bypasses the
  asdf shim, which otherwise needs a `.tool-versions` in the cwd) with `-Ilib exe/rush -c`, and
  `chdir` to a fresh `Dir.mktmpdir` for bad-path tests. Bare `ruby` from `/tmp` fails with 126.
- **Every differential probe owns a bounded process tree:** the shared runner gives ordinary
  rush/dash launches a fresh process group but deliberately keeps them in the harness session;
  its 10-second monotonic deadline (`RUSH_PROBE_TIMEOUT` overrides it) always SIGKILLs that group
  and reaps the leader. On Linux a dedicated supervisor subprocess becomes a child subreaper
  and a procfs tracker follows start-time-identified descendants across `setpgrp` and reparenting;
  cleanup stops the closure before killing/reaping it, so a stopped escapee cannot hold capture
  pipes or survive under pid 1. The stopped-job helpers keep their explicit `setsid` argv and
  must NOT also use `pgroup: true`: a process-group leader cannot call `setsid`, so util-linux
  would fork and detach the status/cleanup handle. This is one cleanup implementation with two
  preserved session topologies, not global session isolation disguised as timeout handling.
- **Fuzzers are ad-hoc**, kept in the session scratchpad, not the repo. Their product is the
  divergences they surface, which get distilled into the differential corpus (deterministic,
  fast, dash-gated) and into beads issues.
- Don't pass shell programs through `.inspect` / naive single-quote escaping in harnesses
  (backreference + re-escaped newline bugs); pass them as direct argv elements or env vars. And
  note rush does **not** set `$1`/positionals after `-c` (only dash does) — `$1`-based harnesses
  silently break.

---

## Dev tooling (beyond rubocop + rspec + coverage)

Tool-state verified on Ruby 4.0.5 (so it isn't re-researched). Beads epic `rush-211`.

### reek — a forward ratchet, not a judge of the existing code (`.reek.yml`)
reek 6.5.0 has no *official* Ruby 4.0 support (lists 3.0–3.3) but **works**: it parsed all 111
`lib` files with zero parse errors via `parser` 3.3.11.1 (rush uses no 3.4+ syntax — the `it`
implicit param, etc.). Out of the box it flagged ~292 smells, but nearly all are **deliberate or
redundant here**: metric detectors (TooManyStatements/Methods/…) duplicate the Sandi-Metz limits
RuboCop already owns; UtilityFunction/FeatureEnvy/DuplicateMethodCall/Attribute are the
intended functional + AST-visitor style; NilCheck/ControlParameter/BooleanParameter are
legitimate; IrresponsibleModule mirrors the deliberately-off `Style/Documentation`; and a few are
plain false positives (`waitpid2`, `exit!`, the Racc `parser.rb`, the ParserSupport mixin). So
`.reek.yml` disables those (each with a one-line reason) and accepts single-letter names, leaving
**zero residual** — reek's real value here is catching *new* cryptic names / smells, not
re-judging reviewed code. Honest caveat: after this tuning reek's marginal signal over RuboCop is
thin; it is kept as a cheap ratchet. `exclude_paths` is matched against the *given* paths, so it
must be relative (`lib/rush/parser.rb`) and reek run from the repo root, as the rake task does.

**Update (rush-6hi): the "deliberate" hand-waves above were re-examined and the ratchet
tightened.** All thirteen non-metric detectors that were blanket-`enabled: false` are now ON
(one slice each, `35d5abf..59704c8`); only the five that duplicate RuboCop's Sandi-Metz Metrics
(`TooMany*`, `LongParameterList`) stay off, since RuboCop owns those thresholds. Re-reading every
hit produced *real* refactors, not just config: a `WordScanner.next_word/.entire` factory pair
(killed a boolean), a `PipelineRunner::Stage` value object owning the pipe-fd topology
(`Stage#io`), `HereDoc#fill`, ~19 nil-checks rewritten to truthy/`unless`, table-driven
`SubstitutionReader#adjust`, and locals for genuinely-repeated calls. Where a smell was *not*
real, the detector stays enabled with a **scoped, code-grounded** `exclude` (not a blanket
disable). Findings worth not re-learning:

- **reek `exclude` strings are `Regexp.quote`d and matched UNANCHORED** against the full context
  name. So `?`/`#` in a method name work literally, but `Rush::Lexer` also matches
  `Rush::Lexer::SubstitutionReader` — to scope to one class with nested classes, use an inline
  `# :reek:SmellName` directive on the class instead (see `Lexer`).
- **reek can't see helper-initialised ivars or inherited `initialize`.** `setup`/`init_state`/
  `initialize_runtime` exist for `Metrics/MethodLength`, so reek's per-method
  `InstanceVariableAssumption` misfires on `Lexer`/`ShellState`/`Executor`; builtins read `@io`
  via Base's inherited `#io` accessor (or are excluded where the accessor would breach `AbcSize`).
- **Detectors conflict.** Hoisting a repeated `@ivar.method` into a local to satisfy
  `DuplicateMethodCall` turns a self-state read into an external referent and trips `FeatureEnvy`;
  so repeated ivar accessors (`@ref.op`, `@executor.state`) keep the call and are excluded. Set
  `DuplicateMethodCall max_calls: 2` (twice is idiomatic; 3+ earns a local).
- **Stateful reads look like duplicates.** `@scanner.getch` / `@scanner.matched` return a
  *different* value each call — "caching" them is a bug, so they are never extracted.
- **`UtilityFunction public_methods_only: true`** is the right scope: private pure helpers are the
  intended small-transform style; the only public state-less methods left are the `SystemCalls`
  port (must stay instance methods for the injected fake) and a registry strategy `#apply`.
- **IrresponsibleModule** mirrors the off `Style/Documentation`, but since that cop is off reek is
  the *sole* doc enforcer (no duplication), so it is enabled and the ~10 gaps were documented.

### types — two independent checkers (RBS/Steep ⟂ Sorbet)
**Decision superseded.** The earlier "RBS *over* Sorbet" rationale is dropped: per the Charter,
rush runs **both** RBS/Steep (sig/*.rbs, external) and Sorbet (inline `sig {}`) independently and
compares how each fares. RBS/Steep = rush-211.2 (this section); Sorbet = rush-211.4.

#### RBS/Steep rollout — slice 1 (infra + green baseline)
`steep 2.0.0` + `rbs 4.0.3` (dev deps), a `Steepfile` targeting `lib/`, `sig/` bootstrapped with
`rbs prototype rb` (mostly `untyped` skeletons), and `steep check` wired into the default `rake`
gate. Gradual by design (the bead anticipates it): **108 / 122 files checked**, 14 `ignore`d with
per-file reasons in the `Steepfile`, ~**54% of calls typed** at baseline (rbs core types the
stdlib/syscall calls even before our own sigs are tightened). `Ruby::UnannotatedEmptyCollection`
is silenced while sig/ is untyped — it's pure bootstrap noise, re-enabled as types land.

Findings worth not re-learning (the research payoff of running the tool hard):
- **Steep 2.0.0 crashes internally on two of rush's core patterns**, and *swallows the crash* —
  it logs `FATAL` to stderr, skips the file, and still exits 0 with "No type error detected". So
  a crashing file is **silently unchecked, not green**; you must enumerate crashers
  (`steep check 2>&1 | grep FATAL`) and `ignore` them explicitly or the gate lies. The triggers:
  (1) `Data.define` blocks that define methods (`ast/param_ref.rb`, `expansion/arithmetic/nodes.rb`)
  → `Unexpected self_type: untyped`; (2) nested block-param destructuring over a
  heterogeneously-typed hash (`redirection/registry.rb`: `DEFAULTS.each { |kind, (mode, fd)| }`)
  → `to_ary returns non-array-ish type`. rush is AST-heavy with `Data.define`, so this is a real
  limit on how far Steep can go here without upstream fixes.
  - **Root cause + partial fix (rush-211.6).** The crash isn't `Data.define` per se — it's that
    `rbs prototype` emits `Foo: untyped` (a *constant*, not a class) for a `Data.define`-with-block,
    so when Steep checks the block's method bodies the self-type is `untyped` → `for_new_method`
    raises. Declaring the node as a **real class** (`class ParamRef < ::Data` with members +
    methods) gives a concrete self and the crash is gone. But a second, subtler limitation remains:
    Steep attributes **instance** methods written inside a `Data.define do…end` block to the
    *enclosing module*, not the class — so `value`/`op`/`result` resolve against `Arithmetic` and
    fail. **Singleton** methods (`def self.x`) attribute correctly, which is why `param_ref` (all
    `self.`) types green but `nodes`/`pipeline_runner` (instance `def result`/`def last?`) do not.
    **Resolution (rush-211.6 closed).** Define each node as `class X < Data.define(:members)` and
    put the methods in the class body. That's a single class definition (so `Style/Documentation`
    is happy, unlike a `X = Data.define(...)` + reopened `class X`), Steep attributes the instance
    methods to the node, and the crash is gone — `nodes`, `pipeline_runner` (Stage) and `param_ref`
    all type and were un-ignored. One catch: rubocop's `Style/DataInheritance` *mandates* the
    un-typeable `do…end` block form, so it's disabled — another rubocop-vs-steep conflict where the
    cop yields to let the code be type-checked. Net: the Steep ignore list is down to just the
    racc-generated `parser.rb` and `number.rb` (the `Style/SymbolProc` conflict) — both irreducible.
- **rbs 4.0 core declares `spawn`/`exec`/`fork`/`exit!` only on `Kernel`, not `singleton(Process)`**
  — so `Process.spawn(...)` trips `Ruby::NoMethod` while `Process.waitpid2/pid/times/kill` resolve
  fine. A core-RBS modelling gap, not a rush bug.
- **Racc isn't typed**: the generated `parser.rb` is excluded (sig-gen + check); a hand stub
  `sig/rush/parser.rbs` lets the rest resolve the `Parser` constant. `ParserSupport`'s host methods
  (`do_parse`/`token_to_str`, from `Racc::Parser`) are unmodelled, so that file is deferred too.

#### Tightening pattern: value-level invariants under strict coverage pressure
Recurring across the hand-typing batches (`Status.of`, `Scope#declare_local`/`#end_scope`,
`CommandLookup#verify`, `Environment#exported`): the code is correct because of an invariant the
type system can't see — *absent exitstatus ⟹ present termsig*, *the popped frame is non-nil
because it's paired with begin_scope*, *terse is only called behind a `known?` guard*. Steep flags
these as `NoMethod`-on-`nil` (or on a union member). The **coverage pressure shapes the fix**: the
obvious nil-guards (`x || default`, `x&.m`, `return unless x`) all add a branch whose
invariant-false side is unreachable and therefore untestable noise. So instead **pin the type with
a branchless, behaviour-preserving coercion on the only reachable path**:
`termsig.to_i`, `@frames.fetch(-1)` (keeps crash-if-empty), `@frames.pop.to_a`, `*set.to_a` for a
splat Steep won't widen. Where the gap is a guarded union (not nil), model the **abstract base as
the protocol** — `CommandLookup::Match` declares `describe`/`terse` so `find -> Match` covers the
`known?`-guarded call (RBS-only methods need no implementation, like `Positional`'s delegators).
Deliberately **not** used: inline `#:` assertions — they pollute the code and, being RBS comments,
could be read by the Sorbet track too, crossing the two streams we keep independent.

**Instruments can contradict each other.** Typing `TestExpr#binary(*args)` for Steep by spelling
out `binary(args[0], args[1], args[2])` (Steep won't splat a variable Array into a fixed arity)
added two `args` references and tripped **reek**'s FeatureEnvy on `#evaluate`. The fix satisfies
both: pass the array and destructure *inside* `#binary` (`lhs, op, rhs = args`) — `#evaluate`'s
arg-reference count returns to baseline (reek green) and there is no splat (Steep green). General
lesson: a type fix is not done until the *whole* gate is green; one quality tool's preferred shape
can be another's smell, and the resolution is usually a refactor that pleases both, not a
suppression in either.

**Sometimes no shape pleases both.** `Number::UNARY` maps operators to callables; for the plain
unary operators the idiomatic value is `lambda(&:-@)` / `lambda(&:~)` — which **rubocop
`Style/SymbolProc` mandates**, but which **Steep can't type** (it sees `lambda`'s block as
zero-arity and `Symbol#to_proc` as one-arity). The escape forms each lose: `->(v) { -v }` /
`->(v) { ~v }` are themselves `Style/SymbolProc` offenses; `->(v) { v ^ -1 }` satisfies both but is
write-only. **Resolution (chosen later):** the `UNARY` table is *already* a mix of explicit
lambdas (`->(v){ v }` for `+`, `bool(v.zero?)` for `!`), so write `-`/`~` as explicit lambdas too
— uniform with the table — and **disable `Style/SymbolProc` for `number.rb`** (it's the cop that's
wrong here: it would break both the table's own style and Steep). This is the same move as
`Style/DataInheritance` — when a cop fundamentally contradicts the typed code, scope-disable the
cop rather than `ignore` the file or contort the code. So the corollary stands but with a sharper
edge: an empty intersection doesn't force *clarity vs types* — usually the rubocop side is the one
mis-fitting Ruby-3-era code, and yielding the cop keeps **both** clean. After this the Steep ignore
list is just the racc-generated `parser.rb` — every hand-written file is checked.

#### Steep won't infer lambda params inside a *frozen* hash literal
Un-ignoring `number.rb` exposed a deeper gap than the `SymbolProc` clash: even with `UNARY`/`BINARY`
declared `Hash[String, ^(Integer) -> Integer]` in the sig, every operator body was *untyped*
(`number.rb` sat at 64%). The cause is expected-type propagation: Steep pushes a declared value type
into a bare `->(v) { … }` literal only when the literal is in a position it checks *against* that
type. `X = { k => ->(v){…} }.freeze` is not such a position — `Hash#freeze` is typed `() -> self`,
so Steep infers the `{…}` receiver **bottom-up first** (params untyped) and only then matches the
`.freeze` result to `X`'s type; it never re-checks the lambdas against the value type. An *un-frozen*
literal (`X = { … }`) does propagate and types fully — but constants must stay frozen
(`Style/MutableConstant`), and a trailing `#: Hash[…]` on the whole `.freeze` doesn't push inward
either. The fix that keeps `freeze` **and** types the bodies is a per-lambda inline annotation,
one lambda per line: `k => ->(v) { … } #: ^(Integer) -> Integer`. This took `number.rb` 64→98% and
`parameter_forms.rb` (the `${}` `FORMS` table, same shape) 6→100%. RuboCop 1.88 treats `#:` as
first-class: `AllowRBSInlineAnnotation` on `Layout/LeadingCommentSpace` (no leading space) and
`Layout/LineLength` (excluded from the budget) — enabling support, not disabling a cop. Lesson: a
correct *declared* type isn't a checked type; gradual typing only bites where the checker actually
re-derives the value, and lambdas-in-frozen-literals are a blind spot you close at the value, not
the signature.

#### Slice 2 — the runner layer, and "untyped is about the *receiver*"
A second pass drove typed-call **82.9% → ~93%** by typing the layers the spine drives but that were
still on the prototype `untyped`-everything sigs: the runner layer (CLI, CommandRunner, External,
Function/Source/Trap/Pipeline runners, Repl, ProgramReader), the arithmetic cluster (a `node` union
alias gave the AST a real recursive type; the Pratt parser typed to 100%), and a batch of builtins
(set, printf_formatter, kill, test/[). Two boundary annotations did outsized work: `Parser#parse ->
AST::List` (the grammar's start rule) cascades to every parse caller, and a base `WordSegment#expand`
(abstract, like `Node#execute`) made every segment in the expansion pipeline known to expand.

The reframing that made the tail tractable: **`steep stats` counts a call as untyped when its
*receiver* is untyped, not when it returns `untyped`.** `test_expr` looked irreducible — it
dispatches primaries by arity through `send`/`public_send` — but those receivers are `self` / typed
operands, so the calls are *typed*; what was untyped was the argument peeling around them. Typing
`@args`/`@files` took the file 58% → 100% with the dynamic dispatch untouched. So the lever is
almost always "what ivar/param/collaborator is still `untyped`", not "this method is too dynamic".
What genuinely stays untyped is narrow and honest: a value payload deliberately left open
(`WordSegment#value`, `Builtins::Registry`'s class table, `TILDE_EXPANDERS`), and the racc glue
(`parser_support`'s factories mutate racc's untyped value stack). Steep also has handy precision
where it counts — tuple destructuring (`a, b = waitpid2(pid)` types `b` as `Process::Status`), and
`x.class` as `singleton(X)` — but *not* across repeated method calls (`peek && PRECEDENCE[peek]`
needs `peek` bound to a local first; narrowing is for locals, not re-invocations).

#### Coercions move the proof from the checker to runtime — and structure beats coercion
The single most important lesson of the typing work. When Steep flags `x.last[...]` or `match[1]`
because a method's honest return is `T?` (`Array#last`, `MatchData#[]`, `String#[]` are all
nilable), the easy fix is a **coercion** — `fetch(-1)`, `.to_s`, `.to_a` — that gives Steep a
non-nil type. But a coercion does **not prove** the value is present; it *asserts* it, and so
**shifts the proof obligation from the type-checker to runtime + the author's reasoning**. That is
exactly what a type checker exists to prevent, so coercions deserve scrutiny, and they are not
equal:

- **Loud coercions don't hide anything.** `arr.fetch(-1)` raises `IndexError` if the array is
  empty — same crash, same place, just not statically proven. The guarantee moved to a runtime
  bounds-check; nothing is masked.
- **Silent coercions can mask.** `maybe_nil.to_s` → `""`, `maybe_nil.to_a` → `[]`: if the invariant
  is ever violated, a `nil` that *should* have surfaced becomes a benign-looking default and flows
  on. These are the dangerous ones — a real bug would be hidden in runtime, unseen by the checker.

Audit of this codebase's coercions found **no hidden bugs** — each sits on a genuinely unreachable
or behaviour-identical `nil` path (a guard, an in-bounds slice, a total regex, a domain invariant
like Process::Status having exactly one of exitstatus/termsig). But "unreachable by my reasoning"
is weaker than "unreachable by construction", which is the real fix:

**Structure beats coercion.** Where the invariant matters, restructure so the property is
*structural* and the checker proves it for free, instead of asserting it with a coercion.
`IfsScanner` held the in-progress field as `@fields.last` (typed `T?`, "non-empty here" only as a
*positional* invariant — and in fact `result` can empty the array, so even "never empty" was
false); it now holds it as a dedicated `@current` ivar, **always present by construction**. No
`fetch(-1)`, no trust — `@current: Hash` is just true, and (bonus) it's self-state so reek is
happy too. Coerce only where nil is truly unreachable and the coercion is a behaviour-preserving
no-op on the real values; reach for a structural refactor the moment the invariant is load-bearing.

#### Sorbet — slice 1 (the second checker boots, and the first real drift)
The second, independent checker (rush-211.4): `sorbet` (static `srb`) + `sorbet-runtime` (a real
runtime dependency, the accepted trade for inline `sig {}`), a `sorbet/config`, and a `sorbet` rake
task wired into the default gate **next to** `steep` — two type checks over one codebase, as the
charter wants. Sorbet 0.6.13320 runs fine on Ruby 4.0. Baseline is `# typed: false` (Sorbet's
default): even there it resolves constants and rejects a few structural forms, so getting to *green*
already surfaced findings — and that is the point, not a number.

**Invoke the binary, not `srb tc`.** The `srb` wrapper auto-loads every gem-shipped `rbi/` in the
bundle — and prism's ships a self-inconsistent one (`Prism::LexCompat::Result` doesn't exist in
1.9.0) that errors before our code is even read; `--ignore` doesn't suppress it (the wrapper adds
those RBIs outside the ignore path). The raw `sorbet-static` binary (located via its gem,
`libexec/sorbet`) reads only `sorbet/config` → no phantom gem-RBI noise. The rake task calls it
directly.

**The first genuine cross-checker drift: `Data.define`.** Steep and Sorbet have *opposite*
requirements for a Data class with methods, and neither's preferred form is the other's:
- `class X < Data.define(:a)` — **Steep's** chosen form (slice 1). **Sorbet rejects it** outright
  ("Superclasses must only contain constant literals", srb.help/4002).
- `X = Data.define(:a) do def m; end end` (block) — **Sorbet accepts** it; **Steep can't type** the
  block methods (attributed to the enclosing module — the original slice-1 finding).
- `X = Data.define(:a)` + reopened `class X; def m; end; end` (assignment + reopen) — **both accept
  it.** This is the resolution: the two checkers' constraints *intersect* to a single form, and it's
  arguably cleaner than either's favourite. A nice charter result — the second checker didn't just
  duplicate the first, it *narrowed* the design.

That form isn't free, though: it ripples into the linters, because reek and RuboCop disagree about
where a reopened-class's doc comment lives. reek's `IrresponsibleModule` sees **two** definitions of
`X` (the `Data.define` assignment *and* the `class X` reopen) and wants a comment on each — one
comment can't satisfy it. RuboCop's `Style/Documentation` wants the comment on the reopen and is
content with one. So for these classes the usual split is inverted: RuboCop holds the doc gate
(comment on the reopen) and reek's `IrresponsibleModule` exempts them (`.reek.yml`). Two more small
Sorbet⟂linter frictions, same flavour: an anonymous block splat `{ |*| … }` (the old closed-fd
sentinel's EBADF stubs) is fine for RuboCop but Sorbet forbids it (srb.help/3012) — naming it
`|*_|` satisfies Sorbet but trips reek's `UncommunicativeVariableName` (the project accepts only
`e`). **Lesson so far:** adding a second type system to existing code mostly costs you at
the *structural* seams (class shape, splat syntax) the first system and the linters had already
pinned — and each clash is a small, real piece of "how these tools see Ruby differently", which is
exactly what this project is for. (Inline `sig {}` and raising `# typed:` levels: next slice.)

#### Sorbet — slice 2 (raising `# typed: true`)
`# typed: false` barely checks anything (syntax, constant resolution); the gate only earns its keep
at `# typed: true`, where Sorbet checks method existence on typed receivers, arg counts, and dead
code — even with no `sig {}` yet (everything inferred as `T.untyped`). Tagging all of lib+exe `true`
surfaced just **22 errors**, and **117 of 122 files now sit at `# typed: true`** with srb green.

What got there cleanly: a `Rush::Parser` RBI shim in `sorbet/rbi/shims/` (the Racc-generated
`parser.rb` is excluded, exactly like Steep's `parser.rbs` stub — the *one* place the two type
systems' stubs are deliberately parallel; `sorbet/config` had to add `--dir ./sorbet/rbi` because the
raw binary, unlike `srb`, doesn't auto-read it), and `Kernel.raise` in LoopControlHandling (a bare
`raise` in a mixin has no resolvable self).

Five files stay `# typed: false`, each a concrete Steep⟂Sorbet drift (Steep types them; Sorbet
can't, or mistypes):
- **`Integer(x, exception: false)`** — Sorbet's RBI types it **non-nil**, so the `… or raise` /
  `… || invalid` nil-fallback reads as dead code (srb.help/7006). Steep/rbs models the nilable
  return correctly. Hits `number.rb` and `printf_formatter.rb`.
- **non-static splats** (srb.help/7019) — `send(sym, *args)` (test/[ arity dispatch) and
  `Process.spawn(env, [cmd], *argv.drop(1), opts)` (the splat isn't terminal — `opts` follows).
  Steep accepts both. `test_expr.rb`, `system_calls.rb`.
- **`module_function` + Kernel** — in `number.rb` Sorbet can't see `Integer`/`raise` on the module's
  singleton self; Steep resolves them.
- **Racc host methods** — `parser_support.rb` is mixed into the generated parser and calls
  `do_parse`/`token_to_str` from the `Racc::Parser` superclass Sorbet never sees.

Each is fixable with an inline escape (`T.unsafe`, a `Kernel.Integer` shim) — but `T.*` in the
shared source would break *Steep* (no RBS for the `T` DSL), so reclaiming these is bound up with the
inline-`sig {}` work, which needs an RBS bridge for `T`/`T::Sig` so Steep tolerates the Sorbet
annotations on the same files. That bridge — and `sig {}` on the public API — is the next slice.
The standing lesson holds: the second checker pays off not as a number but as a list of precise
spots where it and the first disagree about Ruby.

#### Sorbet — slice 3 (inline `sig {}`, and the bridge that lets Steep ignore it)
The deliberate design: RBS in `sig/*.rbs` for Steep, inline `sig {}` for Sorbet — *over the same .rb
files*. So the blocker isn't writing sigs, it's that Steep reads the same source and doesn't know the
Sorbet DSL. The fix is a small RBS bridge (`sig/sorbet_dsl.rbs`): the trick is the **block self**.
A `sig { returns(Integer) }` block, declared as `def sig: () { () [self: T::Private::DeclBuilder] ->
void }`, runs (to Steep) against Sorbet's real builder type — so `params`/`returns`/`void` resolve as
its methods and the *types inside the block are never cross-checked by Steep* (exactly the wanted
independence). `[self: untyped]` did NOT work — Steep kept self as the enclosing class and flagged
`returns`; a concrete builder class is what binds. A class using `sig {}` adds `extend T::Sig` in
**both** its `.rb` (for sorbet-runtime) and its `.rbs` (so Steep finds `sig` on the singleton). Most
of `T`'s value surface (`T.unsafe/cast/must`, `T::Boolean`) stays untyped in the RBS bridge — a sig
block's *types* are Sorbet's, deliberately not Steep's. `T.let` is the narrow exception: the bridge
models it as identity (`[X] (X, untyped) -> X`) so inline Sorbet casts inside real expressions do not
turn otherwise typed Steep calls into untyped calls; the type object itself is still opaque to Steep.

`Status` is the first class carrying real `sig {}` (proves it on both checkers + at runtime), and two
findings fell out immediately:
- **sorbet-runtime is a *runtime* type check — which RBS/Steep simply is not.** `Status.new("x")`
  raises `TypeError` at runtime from the `sig`. Real capability, real cost: the suite injects
  `instance_double(Process::Status)` into `Status.of`, which isn't `is_a?` the class, so runtime
  validation rejects the double. Resolution: production keeps runtime validation; tests install
  `T::Configuration.call_validation_error_handler = ->(*) {}` so doubles pass (the static `srb tc`
  gate still covers types). The two type systems now differ in *kind*, not just notation — Sorbet
  validates at the call, Steep only ahead of time.
- **typing one class ripples into its callers' inference.** Giving `Status.success` a return type made
  the loop runners' `status` variable `Status`, then the still-unsig'd `#iterate` reassigned it to
  untyped — and Sorbet forbids a variable changing type across a loop/block (srb.help/7001). Fixed
  with `T.let(Status.success, Status)` to pin it (the bridge treats `T.let` as returning the value's
  own type, not as a Steep check of Sorbet's type object). Gradual typing isn't local: each sig you add
  is a small obligation on everything downstream.

The bridge makes the rest of the `sig {}` rollout mechanical; it proceeds class by class.

#### Sorbet — slice 4 (the full rollout, and what a second checker is *for*)
`sig {}` now covers the whole codebase: **110 classes carry `extend T::Sig` and ~690 `sig {}`
blocks**, 116 files at `# typed: true`, 5 at `# typed: false`, full gate green. Where a file's RBS is
already untyped (e.g. `command_substitution`, most thin builtins, the `*_runner` shells), the Sorbet
sig faithfully mirrors that with `T.untyped` — the two sig sets track each other, including their
gaps. The rollout was done cluster by cluster (value objects → AST → lexer → expansion → builtins →
spine), each gated fully green before commit; the gate (not trust) is what keeps the sigs honest —
a wrong sig fails `srb tc` *or* sorbet-runtime *or* a spec.

The payoff is the list of places the two checkers genuinely diverge — each a small truth about how
they read Ruby:
- **`Integer(x, exception: false)`** — Sorbet's RBI types it non-nil, so the nil branch is "dead
  code" (7006); rbs models the nilable. (Two files stay `# typed: false` for it.)
- **`File.writable?`** — Sorbet's stdlib RBI mistypes it `T.nilable(Integer)` (it returns Boolean,
  unlike its siblings `readable?`/`executable?`); needed a `!!`.
- **`Base#stdout`/`#stderr`** — RBS says `IO`; Sorbet's *runtime* `is_a?(IO)` rejected the old
  closed-fd sentinel (from `>&-`) that quacked like IO, so the Sorbet sig stayed `T.untyped`. The
  sig sets diverged on purpose — runtime validation forced a looser nominal type than static
  checking needed.
- **literal-symbol narrowing** — `parse -> AST::List | :eof`: Steep narrows on `== :eof`, Sorbet
  can't (it widens `:eof` to `Symbol`), so the call sites need `T.cast(program, AST::List)`.
- **string-literal union types (a drift that *doesn't* materialise)** — RBS can spell
  `("+" | "-" | "!" | "~")`; Sorbet has no string-literal types at all. So `Number#unary`'s `op`
  *looked* like a place RBS could out-type Sorbet. It can't: `op` is a parser token validated only at
  runtime (`UNARY.include?` then `.fetch`), and `Parser#advance` returns plain `String` with no
  static narrowing anywhere, so feeding a union would need an unchecked `cast` — an escape no better
  than `T.unsafe`. Both checkers land on `String`, the honest maximum. The lesson: a literal type is
  worth more than `String` only where the value is *statically* narrow; a runtime-validated token is
  not, so the more-expressive notation buys nothing here. (Tightened `unary`/`binary` `op` and
  `bool`'s `flag` off `untyped` in the same pass; `Evaluator#assign` slices `op.chop`, not
  `op[0..-2]`, so the operator key is a non-nil `String`.)
- **`x && y` returning the falsy operand** — harmless to Steep, but sorbet-runtime rejects the `nil`
  against a `bool` sig at the call; rewritten as ternary / `!!` throughout.
- **abstract methods** — typing `CommandLookup#find -> Match` exposed that `Match#describe`/`#terse`
  were only on subclasses; added base raises (the `Node#execute` precedent).

Two systematic costs of *inline* sigs (recorded so future code follows the pattern): (1) a sig'd
block method must name its block `&blk` (the sig references it), which collides with RuboCop's
anonymous-forwarding preference — resolved once in config (`Naming/BlockForwarding: explicit`,
`Style/ArgumentsForwarding: UseAnonymousForwarding: false`) rather than per-method; (2) `sig {}` lines
inflate class length, so two large classes (Executor, WordScanner) carry an inline
`Metrics/ClassLength` disable (annotation, not logic). rush-211.4's core is met: two independent type
systems, in two notations, checking the same code, with their disagreements catalogued rather than
reconciled.

### mutant — usable, on-demand only
mutant 0.16.3 is **free for OSS** (rush is MIT + public; `--usage opensource`, no signup) and
actively maintained. The parse+unparse roundtrip it relies on handled **all 111 lib files
cleanly** (`unparser` 0.9.0), so the `parser/ruby33`-grammar warning is cosmetic. Kept out of the
default gate: it reruns the ~60s suite per mutation, far too slow for a per-slice gate; it belongs
in a `rake mutant` task / CI. Its payoff is exactly what line/branch coverage cannot show —
whether the assertions actually *kill* mutations.

Wired in as an on-demand `rake mutant[Subject]` task (default subject from `.mutant.yml`: `Rush*`,
with generated `Rush::Parser*` ignored just like coverage ignores `lib/rush/parser.rb`). The Mutant
config sets `RUSH_SKIP_COVERAGE=1` so SimpleCov does not overwrite the normal coverage report with
the tiny, mutation-selected test subset. Full-project mutation is intentionally outside
`bundle exec rake`; use subject-level runs while hardening specs, then let CI/nightly take the slow
whole-tree pass. A separate `rake mutant:check[Subject,Threshold]` task reads Mutant's JSON result
and enforces an opt-in mutation score gate (default `Rush*`, `95.0%`) without adding Mutant to the
normal rake pipeline.

### Docker syscall gate — explicit, not the default bar
rush-n5b.19 adds `bundle exec rake docker:test` / `bin/test-in-docker` as the place for
syscall-heavy integration checks that are too host-sensitive for the native fast gate. The task
builds a small Ruby image, mounts the working tree, runs `bundle install --jobs ... --retry ...`,
then runs the normal `bundle exec rake` inside the container before a smoke script exercises a real
`ulimit -Sn 64` path through rush. The non-obvious part: the stock Debian slim `dash` (0.5.12)
failed the existing differential corpus because it lacks the newer `LINENO` and alias-listing
behaviour; the image therefore builds checksum-pinned dash 0.5.13.4 from upstream so the Docker
oracle matches the native development oracle. The smoke calls the actual `Process.setrlimit` in the
rush subprocess, so it verifies the impure port without changing the developer's login shell limits.
The boundary is still Docker's boundary, not magic isolation: daemon policy, cgroups, capabilities,
and `--ulimit` settings decide the container's ceiling.

### `set -o pipefail` — status selection only
`pipefail` is intentionally just a pipeline status-selection rule in `PipelineRunner`: all stages are
still forked, all pids are still waited, and only after that do we choose either the normal last-stage
status or (when enabled) the rightmost non-zero status, falling back to 0 when every stage succeeds.
Keeping it below `AST::Pipeline` means the existing `!` and `set -e` machinery automatically sees the
pipefail-adjusted status: `! false | true` inverts success without pipefail, but inverts failure with
pipefail; `set -e -o pipefail; false | true` aborts at the same leaf `exit_on_error` checkpoint.

### Word expansion boundary — keep segment polymorphism
rush-n5b.17 decided **not** to migrate word expansion to a visitor/registry now. The durable rule is
in `docs/architecture/word-expansion-boundary.md`: `WordSegment#expand` is scalar and kind-local
(literal / parameter / command substitution / arithmetic), while `Expansion::Pipeline` owns the POSIX
ordering context — tilde mode, `$@` field breaks, quote escaping, IFS splitting, and globbing. This
keeps the existing `Node#execute`-style polymorphism without letting AST payload classes absorb word
expansion as a whole. Revisit only if new segment kinds need cross-segment state, segment classes grow
real algorithms, the pipeline starts type-switching on segment subclasses, or `WordSegment#value`'s
open type becomes the dominant type-checking escape.

### Simple command source order — preserve now, spend later
rush-n5b.18 added `AST::SimpleCommand#parts` as the canonical source-order list of assignment,
word, and redirect objects, with `#assignments`/`#words`/`#redirects` derived from it so existing
execution callers keep their API. The decision is recorded in `docs/architecture/simple-command-order.md`.
The useful dash probes while deciding: command-word substitutions are expanded before command
redirections (`echo $(echo err >&2) 2>f` leaves `f` empty), but assignment substitutions attached to a
command or to a no-command assignment/redirect see same-command redirections (`X=$(echo err >&2) true
2>f` and `X=$(echo err >&2) 2>f` write `err` to `f`). rush's stored order is now available for future
POSIX 2.9.1 execution fixes instead of being lost at parse time; the concrete redirection/assignment
substitution fix is tracked as `rush-n5b.20`.

### Assignment command substitutions see same-command redirections
rush-n5b.20 fixed the first semantics found while deciding simple-command source order. POSIX/dash
split simple-command expansion into phases: command words are expanded before command redirections, so
`echo $(echo err >&2) 2>f` leaves `f` empty; assignment RHS expansion happens after those redirections
for both an external command and a no-command assignment/redirect, so
`X=$(echo err >&2) /bin/true 2>f` and `X=$(echo err >&2) 2>f` write `err` to `f`. The bug was not the
parser order anymore — it was
that `RedirectScope` yielded the redirected `IoTable` without rebinding `Executor#io`, and
`CommandAssignments` expands through `executor.expander`, whose command substitutions consult
`executor.io`. Fix: keep argv expansion before `with_redirects`, but wrap only assignment persistence
/ external environment construction in `executor.with_io(io)`. That threads redirects into assignment
substitutions without making command-word substitutions observe them.

### Phase 4 split — the platform boundary runs through it
Unfreezing phase 4 surfaced a framing worth keeping: **rush without job control is already a
conforming POSIX shell**. `set -m`, `fg` and `bg` are User Portability options in POSIX.1-2017,
not part of the mandatory §2 core (dash builds with `--disable-jobs` and still ships as
`/bin/sh`), so phases 0–3 complete the mandatory shell language. rush's real platform is
"POSIX as exposed by the Ruby VM": everything through phase 3 fits inside what core Ruby
exports (`fork`/`pipe`/`waitpid2`/`spawn`/`trap`). Job control is the first feature that steps
outside — Ruby has no `tcsetpgrp` binding at all. Verified on Ruby 4.0.5: no TIOC*/pgrp
constants or methods in `IO`, `Fcntl`, `PTY` or `Socket::Constants`; the only relevant export
is `Process::WUNTRACED`. Decided approach for when job control lands: `IO#ioctl` (core Ruby)
with per-platform `TIOCSPGRP` constants keyed on `RbConfig::CONFIG['host_os']` — `0x5410` on
Linux (asm-generic; powerpc/sparc/mips number ioctls differently), `0x80047476` on darwin/BSD —
with Fiddle-into-libc as the fallback if the constant table grows unwieldy.

Phase 4 is therefore split along that boundary. `rush-mw1` is rescoped to the **interactive
shell only** — portable, in-platform, cheap to verify; the `Repl` baseline with PS2
continuations and error-resumed sessions already exists — and sliced into `rush-mw1.1`–`.6`
(detection/`-i`/`$-`, PS1/PS2 expansion, Reline, §2.8.1 error semantics, interactive signals,
startup files). Job control moved to a new epic `rush-mv8`, deferred again: it is Unix-only by
OS physics, not by implementation language (Windows has no POSIX process groups, no
SIGTSTP/SIGCONT, no controlling terminal — every "POSIX shell on Windows" ships an emulation
layer instead), so it gets a platform gate when it lands. The key design risk recorded on the
epic: **waitpid ownership** — a SIGCHLD self-pipe reaper doing `waitpid(-1, WNOHANG|WUNTRACED)`
steals statuses from the synchronous `waitpid2` calls in `PipelineRunner`/`BackgroundRunner`,
so all child reaping must be centralized into one owner (a job table the synchronous waits
consult) before any job-control feature can land.

### Interactive-shell detection — dash's $- order, and `set -i` as a dash extension
Implementing sh invocation (rush-mw1.1) produced durable oracle findings. (1) dash renders $-
in the **reverse of its internal optlist order** — empirically `uaCvxsife` for the letters rush
supports — neither alphabetical nor flag-setting order; `Options::DASH_ORDER` pins it so corpus
lines printing $- compare equal. (2) dash accepts `set -i` / `set -s` at runtime (its `set`
shares the invocation option parser), toggling flags POSIX's `set` does not define; rush's set
keeps its ignore-unknown-letters policy, so `set -i` is a silent no-op — accepted divergence,
the standard is silent. (3) `dash -o` with **no argument** at invocation prints the `set -o`
settings table claiming every option is "on" (a dash quirk that looks like a bug); rush rejects
it with "-o requires an argument" per the synopsis. Two behaviour fixes rode along: `rush -c`
with no command string used to run an empty program successfully — now an invocation error,
exit 2, like dash; and a script-file operand (`rush file.sh args...`) used to be silently
ignored in favour of stdin — it now runs the file with $0/positionals set. Auto-interactivity
follows POSIX (stdin AND stderr both ttys) rather than probing dash's tty behaviour, which a
pipe-based oracle cannot observe.

### PS1/PS2 prompts — parameter expansion only, and the ParamScanner extraction
rush-mw1.2 wired the prompts to the PS1/PS2 variables (defaults `$ ` — `# ` for a privileged
shell — and `> `), re-read at every prompt and subjected to POSIX 2.5.3 **parameter expansion
only**: `$name`/`${...}` expand; command substitution, arithmetic, backticks, tilde and
backslashes stay literal. Probed dash: modern dash does expand PS1 parameters
(`PS1='[$PWD]$ '` prompts the cwd) but does not do the `!` history-number replacement (a UP
feature rush also skips — no history yet). A prompt is the one expansion context that must
never kill the session, so a malformed value (unterminated `${`, failing `${x?}`) falls back
to the raw string instead of raising. The prompt scanner would have been the third copy of the
lexer's read-a-$-reference logic, which forced the extraction HeredocBody's comment had
deferred: `Lexer::ParamScanner` now serves DollarScanner (raising IncompleteInput so an
interactive word can ask for another line), HeredocBody and Prompt::Text (plain ParseError —
their inputs are already complete). Prompts sit on stderr, which the differential corpus
ignores by design, so behaviour is pinned by unit specs; dash parity was checked by hand.

### Interactive §2.8.1 audit — errors must publish $?=2, and cd exits 2
rush-mw1.4 diffed `rush -i` against `dash -i` across the POSIX 2.8.1 error table (piped stdin:
prompts and diagnostics land on ignored stderr, so `[stdout, exitstatus]` stays comparable —
the trick that makes interactive semantics differentially testable at all). The shell already
survived every error class correctly; what it got wrong was **$?**: dash publishes 2 after a
reported interactive error — the same status a batch abort publishes — while rush left $?
untouched. `Repl#recover` now mirrors `Source#abort_with`. The sweep also caught a plain batch
bug the corpus had never probed: cd's failure status was 1 where dash exits 2 (POSIX only asks
for >0; the oracle wins) — fixed and pinned in the language corpus. Also confirmed: `set -e`
exits even an interactive shell, and `exit` with a bad operand ends the session with status 2,
in both shells. The 2.8.1 interactive column is now a permanent differential corpus file
(spec/integration/differential/interactive_spec.rb).

### Startup files — dash's rules, and what real /etc/profile taught the parser
rush-mw1.6 added login/ENV startup (Startup, run by ProgramSession before the main input).
The dash-probed rules: a login shell (`-l`, or argv[0] starting with `-`; no $- letter) runs
/etc/profile then $HOME/.profile before ANY input — including `-c` commands; an interactive
shell (including `-i -c`) then runs the file named by ENV, its value parameter-expanded
(ParamText, extracted from Prompt for exactly this reuse); missing files and unset HOME skip
silently; `exit` in a profile ends the shell with that code; `return` is bounded to its file
like a dot script, leaving its code in $?; errors follow the session's policy — a batch login
shell aborts (status 2), an interactive one reports, publishes $?=2 and carries on. Login
differential tests are deliberately absent: they would execute the host's real /etc/profile
(host-sensitive); ENV paths are covered differentially with controlled files, login logic by
unit specs. The valuable accident: **running this host's real /etc/profile{,.d} through rush
surfaced two parser gaps dash handles** — a `case` whose last item omits `;;` before `esac`
(POSIX 2.9.4.3 makes it optional; rush requires it — /etc/profile's append_path) and
backslash-newline line continuation (POSIX 2.2.1 — unsupported: misparses an export list in
locale.sh, and after `&&` it crashes with IndexError instead of a diagnostic, gawk.sh). Filed
as rush-x27 and rush-v9t, with rush-9q8 to re-audit the whole profile.d corpus once they land.
Real-world scripts are a fuzz corpus the differential suite doesn't reach.

### case per POSIX 2.10.2 — the lexer owned half the bug
rush-x27 looked like a grammar fix: add the POSIX `case_list_ns`/`case_item_ns` productions so
the last item may omit `;;`. Adding them changed nothing — because the **lexer** only
classified `esac` as the Esac token in the case_arm mode (right after `;;` or `in`); inside an
item's command list it fell through to the RESERVED table, which lacked it, so the parser never
saw the closer. POSIX 2.4 makes esac a reserved word in command position: the missing half of
the fix is one RESERVED entry, and the existing compound-context stack already restores the
enclosing mode when a closer token arrives, so nested cases needed nothing. Bonus alignment: a
stray `esac` is now a syntax error, status 2, exactly like dash. The same slice added the
optional `(` before patterns (also 2.10.2) — which turned out to be flatpak.sh's actual blocker
(`(*":$share_path:"*)` items), not the `$( (` shape rush-9q8 suspected. The real /etc/profile
now parses and sources profile.d up to gawk.sh, whose backslash-newline crash is rush-v9t.

### Backslash-newline — three seams, one rule, one documented divergence
rush-v9t: POSIX 2.2.1 removes an unquoted backslash-newline *before tokenization*. rush
implements it at three seams instead of a character-level filter. Between tokens it is skipped
like blank space (the lexer's INSIGNIFICANT pattern) — except at the very end of the buffer,
where it is deliberately left for the word scanner. Inside words, double quotes and heredoc
data, the scanners drop the pair; when the pair ends an *accumulating* buffer the word scanner
raises IncompleteInput — the same mechanism as an unterminated quote — so ProgramReader pulls
the next line and the REPL shows PS2, while the reader's final at-EOF parse (interactive:
false, the unterminated-heredoc mechanism) just drops the pair, exactly like dash reading a
file that ends mid-continuation. A bare backslash before EOF stays literal (dash-verified:
`dash -c 'echo a\'` prints `a\`). The bead's IndexError crash was the empty-word path — a
continuation-only "word" built an AST::Word with zero segments; it can no longer be reached.
One divergence, documented and deferred (rush-u9x, P4): dash splices at the character level, so
`&\<newline>&` joins into `&&`; rush's operator matcher does not see through the pair.
With this and the case fix, **the full real-host startup corpus is clean**: `rush -l` on this
Arch box runs /etc/profile plus every /etc/profile.d/*.sh to completion (rush-9q8 closed) —
the login shell works against unmodified system files.

### Interactive signals — self-kill probes make dispositions differentially testable
rush-mw1.5. Interactive shells install INT/QUIT/TERM as handler *blocks*, never SIG_IGN: a
Ruby handler resets to the OS default across spawn/exec so children stay killable, where
SIG_IGN would be inherited. INT's handler raises Interrupted at the next VM safe point — it
unwinds the current line back to the session (Repl#survive publishes $?=130 and re-prompts; an
interactive `-c` exits 130 through its EXIT trap), aborts the REPL's blocking read, and
SystemCalls#waitpid2 retries EINTR-style so an interrupted foreground wait still reaps the
dying child instead of leaking a zombie. TrapRunner grew a base-disposition table: `trap`
overrides the interactive defaults, `trap - SIG` restores *them* rather than the OS default
(dash-verified), and subshells drop them so a forked child dies on ^C. Two lessons worth
keeping. (1) Signal.trap invokes handlers with the signal number; a strict `-> {}` lambda dies
with ArgumentError — invisibly, because the failure happens in trap context — so handlers must
be non-lambda procs. (2) `kill -SIG $$` from inside the shell exercises every disposition
without a pty: ignore, abort-line-with-130, trap override, `trap -` restore and subshell
default are all plain differential corpus lines now, stable because Ruby delivers the pending
trap at the very next safe point after the kill builtin returns.

### Reline — one seam, pty proof in the Docker gate; the interactive epic closes
rush-mw1.3 finished phase 4's interactive epic. Reline (ships with Ruby; now an explicit
gemspec dependency) is a single SystemCalls seam: `edit_line` draws the prompt on stderr like
the plain path and records in-memory history, and is used only when stdin is a tty — pipes and
specs keep the raw read_line path, so the entire differential and unit surface is unchanged.
One subtlety: Reline strips the trailing newline ProgramReader needs to keep lines apart;
Repl#edited_line restores it. The :nocov: boundary is real-terminal-only, so its end-to-end
proof is a pty smoke (docker/reline-smoke.rb, wired into the Docker gate beside the ulimit
one): spawn `rush -i` on a pseudo-terminal, watch PS1 get drawn, run an edited line, confirm
`exit 7` survives the editor. With slices 10b–10i the epic is complete: rush is an honest
interactive POSIX shell — invocation detection, PS1/PS2, §2.8.1 error policy, startup files,
signal dispositions, line editing — all inside the Ruby-VM platform boundary the phase-4 split
drew. Job control (rush-mv8) remains the deferred out-of-platform epic.

### Operators see through backslash-newline — the last 2.2.1 seam closes
rush-u9x, the divergence slice 10g documented: dash splices continuations at the character
read (`pgetc_eatbnl`), so `&\<newline>&` is `&&`; rush's operator matcher matched literal
operator text and produced two `&` tokens. The fix is not a character-level filter under the
whole scanner — single quotes forbid that (the pair is literal there), and 10g's seams already
cover words, quotes and heredoc data. Instead, the fourth and final seam: OperatorTable::PATTERN
interleaves `(?:\\\n)*` between the characters of every multi-character operator (maximal-munch
order unchanged — alternation still tries longest originals first), and the lexer splices the
pairs back out of the match before the table lookup, so the emitted token carries the logical
operator. The same blindness hid in IO_NUMBER's lookahead — `2\<newline>>f` must still redirect
fd 2 (dash-verified) — one `(?:\\\n)*` in the lookahead fixes it, and the between-token
INSIGNIFICANT skip already swallows the pair once the digits are consumed. Interactive PS2
needed nothing new: `true &\` at buffer end matches the short `&`, the trailing pair reaches
the word scanner, IncompleteInput pulls the next line, and the re-lex of the joined buffer sees
the spliced operator — dash's prompt behaviour for free from 10g's mechanism. Splitting `<<-`
as `<<\<newline>-` still tab-strips, `>\<newline>&1` still dups (both dash-verified). 300
fuzzed split-operator programs match dash on [stdout, exitstatus] exactly.

### Mutation-hardening the lexer — specs that assert values, and one dead hash key
rush-8v8: `rake mutant:check[Rush::Lexer*,95.0]` scored 90.98% (310 alive of 3435). Three
lessons. (1) **Token-symbol assertions are half a spec**: lexer_spec's `symbols` helper drops
values, so `[:IO_NUMBER, nil]`, `[symbol, nil]` and `Integer(digits, 9)` all survived — killed
by asserting whole `[symbol, value]` pairs and segment `[value, quoted]` shapes. (2) **A
dedicated spec file changes Mutant's test selection**: TokenClassifier and SourceLines had no
`describe` of their own, so their mutations ran against lexer_spec; adding
token_classifier_spec/source_lines_spec *replaces* that selection, so the new file must cover
everything the old one killed or the score drops. Direct state-machine specs on LexState
(drive `advance`, assert predicates with strict `be(true)/be(false)`) took it from 135 alive
to 7. (3) **A surviving mutant can be a code finding, not a spec gap**: the OPENERS entry for
subshells was written `'(': ')'` — a *symbol* key `:'('`, unreachable because the lexer emits
the *string* `'('` — so the compound stack never saw subshells and the guard mutants were
unkillable; fixing the key to `'(' => ')'` made the guards observable (a later-arm `(pattern)`
must not restore case_arm) and behavior stays corpus-identical. The 53 still-alive (98.46%,
gate green) are catalogued equivalents: sig-noise (`T.let` generics, `T.must`), guards
provably redundant under spec_helper's silenced sorbet call-validation (`capture(nil)`,
`lookup`'s nil check, `unless literal`), `if/else nil` truthiness twins, and defensive
branches unreachable through real token streams (dash rejects `case<newline>subject`, so
forced case_subject classification can't be observed). Chasing those would pin implementation
noise, not behavior.

### wait lands on a centralized JobTable — the reaper risk dissolves as a standalone slice
rush-iwh. Two discoveries reframed the deferred job-control epic. First, `wait` was missing
entirely — `rush: wait: not found`, 127 — and it is a **mandatory XCU builtin**, not part of
the fg/bg User Portability option: a hole in the phase-3 core, not job control. Second, more
than half of rush-mv8 turns out to be differentially testable without a pty (dash keeps a job
table, `wait`, `jobs` and `%id`s working with no `set -m` and no terminal). The slice
implements the epic's prescribed first move on its own: `JobTable` is now the **single owner
of child reaping** — External, PipelineRunner, SubshellRunner and CommandSubstitution all wait
through `JobTable#await`. While no background job is running, await targets its pid directly
(so every existing pid-specific spec stub still holds); once an async list has launched it
reaps `waitpid2(-1)` and files foreign statuses — a background job's under its pid, a sibling
foreground child's in a stash its own await consults first. That routing is what makes
`false & sleep 0.3; (wait $!)` match dash's `sub=1`: the parent reaps the dead job *during*
the foreground sleep, so the fork inherits a remembered status. Background statuses stay
remembered after reaping (`wait $!; wait $!` answers twice, dash-verified); background
zombies now get collected by any foreground wait as a side effect. Oracle findings worth
keeping: `wait`'s operand parser accepts an explicit `+`, eats one leading `--`, reads `-5`
as an illegal *option* but bare `-` as an illegal *number*, and overflows past INT_MAX like a
non-numeric (all status 2, shell carries on — a regular builtin, so no BuiltinError); waiting
in a subshell for the parent's child hits ECHILD, which dash maps to status 0. One divergence
where the standard wins over the oracle: POSIX gives an unknown *last* pid operand its 127
(`wait $! 99999` → 127; bash agrees), while dash keeps the last known operand's status —
pinned in unit specs, kept out of the corpus. Also kept out: `exit 7 & (wait $!)`, inherently
racy in dash itself (its pre-fork zombie poll decides 7 vs 0); rush defers opportunistic
polling to the epic's jobs/notifications slice. Two ride-along gaps filed: `exit 4 | exit 6`
crashes rush — ExitSignal escapes the pipeline-stage fork block (rush-txc) — and async lists
neither get /dev/null stdin nor ignore SIGINT/SIGQUIT in the child (rush-tbd).

### Pipeline stages are subshell environments — run_stage reuses SubshellRunner
rush-txc, found by the wait slice: `exit 4 | exit 6` crashed rush with an uncaught ExitSignal
traceback out of the stage child's fork block — run_stage ran the body bare, without the
shell-control resolution every other forked body has. The fix is reuse, not new code: a stage
routes through `SubshellRunner#run_body`, exactly like BackgroundRunner already did. The
dash-probed resolution table, now pinned as corpus lines: exit/return end only their stage
(`exit 4 | exit 6` → 6; the real process boundary truncates, `true | exit 300` → 44); a bare
`return` outside any function acts like exit (dash-verified, → 7); loop control is inert
noise (`break | true` breaks nothing, `continue` likewise); an EXIT trap set inside a stage
fires with the stage's io — `{ trap "echo bye" EXIT; true; } | cat` sends bye through the
pipe; and a fatal error (readonly assignment) aborts just that stage with status 2 while the
shell carries on. The `exit 4 | exit 6 & wait $!` corpus line the wait slice had to drop is
restored.

### Async children isolate themselves — /dev/null stdin, soft SIG_IGN, and a Ruby trap gotcha
rush-tbd. POSIX 2.9.3.1/2.11 with job control disabled: an asynchronous list's child reads
stdin from /dev/null (its own redirections may rebind it — a heredoc still wins) and starts
with SIGINT/SIGQUIT ignored. BackgroundRunner#isolate now does both in the forked child. The
dash-probed shape of the ignore is *soft*: a real SIG_IGN — surviving exec into externals and
inheriting into nested subshells at the OS level — but installed OFF the trap table, so
`trap "..." INT` inside the child overrides it and `trap - INT` restores the OS default, not
the ignore (all corpus-pinned). Ordering matters: the subshell trap reset must run before the
ignores — an interactive session's base handlers reinstall OS defaults as they drop, which
would undo them; the repeat reset inside SubshellRunner#run_body is then a no-op. Two
durable lessons. (1) The `kill` right after `&` is a genuine race in dash too: an instant
`kill -INT $!` beats the child's SIG_IGN setup in both shells (130 five out of five), while a
0.1s settle flips both to the ignore — corpus lines carry the settle sleep. (2) Ruby's
`Signal.trap(sig, 'DEFAULT')` is NOT the OS default: it installs Ruby's own handler that
raises Interrupt/SignalException, so a "default" INT died as an uncaught-exception traceback
where dash dies silently by signal (observably the same 128+n status — Ruby re-kills itself —
but with stderr noise). TrapRunner's :default now maps to 'SYSTEM_DEFAULT' (true SIG_DFL);
`trap "..." USR1; trap - USR1; kill -USR1 $$` exits 138 cleanly in both shells.

### Forked children drop the job table — and dash's EV_EXIT had been lying to the probes
rush-rg2, first slice of the terminal-free job-control half. Re-probing subshell wait
semantics falsified a theory this journal recorded two slices ago: `exit 7 & (wait $!)`
returning 7 in dash was not a "pre-fork zombie poll" and not racy — it was **EV_EXIT**, dash's
tail-call optimization. A `( list )` in tail position never forks; the "subshell" probes were
running in dash's main shell, where its own children are waitable. Appending `; echo tail`
forces the real fork, and every shape flips to 127 — live pid, remembered status and unknown
pid alike — with bash agreeing ("not a child of this shell"). The real semantics, now
implemented and corpus-pinned: **a forked child environment starts with no jobs of its own**
(POSIX 2.12) — Executor#enter_subshell (né reset_caught_traps_for_subshell) clears the job
table alongside the trap reset, covering subshells, pipeline stages, async children and
command substitutions in one seam; the value of $! itself survives. One documented divergence
replaces the wrong one: in tail position dash's optimization leaks main-shell wait-ability
(`sleep 0.3 & (wait $!)` → 0 in dash, 127 in rush) — the standard's subshell semantics side
with 127, and such forms stay out of the corpus. dash's cmd-subst has the same leak for a
single-builtin body (`$(jobs)` sees the parent's table where `$(wait $!; echo)` does not).

### The terminal-free job table — jobs, %ids, and dash's shifting + marks
rush-rg2's second slice lands everything job control offers away from a terminal, all of it
pinned by a 37-line differential corpus. The oracle findings that shaped it. **Rendering** is
byte-exact: "[n] mark state" padded so the command column starts at 34 — and stays empty,
because dash keeps no command text off a tty (which is also why %string and %?string match
nothing there: prefix matching runs against blank text; rush mirrors both). **Numbering**
takes the lowest free slot; an emptied table starts at [1] again. **Lifecycle** is asymmetric
and subtle: `wait` never frees an entry (repeats keep answering — the wait slice's b=1), but
`jobs` displaying a finished entry frees it — after which both `wait $pid` (127) and `wait %n`
(No such job) have forgotten it; `jobs -l` frees like the plain form, `jobs -p` frees nothing.
**Marks recompute mid-listing**: freeing each displayed Done entry re-promotes the next to
current before it prints, so three finished jobs all render `+` — rush matched this by
accident of structure (a probe corrected the spec, not the code). **kill %n** targets the
job's process group `-pid`, which does not exist without set -m: ESRCH, "No such process",
status 1, job survives — mechanically identical in rush since its jobs share the shell's
group. Resolution errors come in three dash flavours (No current job / No previous job / No
such job: %X), all status 2, shared by jobs/wait/kill/fg/bg through one JobSpec resolver;
fg/bg resolve first, then refuse ("job %1 not created under job control"). One idiom is
knowingly broken: POSIX blesses `wait $(jobs -p)`, but rush's command substitution is a real
forked subshell that clears the table, so it yields nothing — dash only supports it through
its no-fork single-builtin optimization (the same EV_EXIT family leak the last slice
documented). If that idiom ever matters, the fix is the optimization, not a special case.

### Mutation-hardening the job table — the fake was too kind to tell
rush-mjb ran mutant over the phase-5 subjects: JobTable 91.14%, JobSpec 87.60%, Wait 97.08%,
Jobs 97.40%, NoJobControl 98.85%, Kill 99.78% against the 95% gate. Two systematic lessons
behind the weak spots. (1) **FakeSystemCalls answered pid-specific waitpid2 from the same
child queue that waitpid(-1) drains**, so the mutants that gutted single-owner reaping —
`background_running?` forced false, statuses filed into the stash instead of onto the job
entry, a no-op `poll`, a no-op `wait_all` — all survived: every status still arrived, just
via a later blocking wait. Status-value assertions cannot see the difference; the kills came
from asserting *state transitions* (`running?` flipping across poll/wait_all/foreground
reaps) and, twice, from spying which pid the wait actually targeted — justified because
-1-vs-pid IS the design under test. (2) **A class with no dedicated unit spec is invisible
to mutant even when integration lines cover it**: JobSpec was exercised only by differential
corpus lines, which run rush in a subprocess, so gutting its NUMBER guard (turning %junk
into an uncaught ArgumentError instead of JobError) and flipping Integer's base 10 to 0/11
(observable via %08 and %10) survived; a direct job_spec_spec took it to 100%. A combined
`jobs -l %1` case (dash-probed) killed the split_flag survivors. After hardening: JobTable
98.10%, JobSpec 100%, Wait 98.83%, Jobs 98.18% — the 22 still-alive across five subjects are
catalogued equivalents: T.let generic noise, T.must under spec_helper's silenced validation,
`bad(e)` vs `bad(e.message)` (string interpolation calls to_s, which is message), `!=` vs
`!eql?`/`!equal?` on deduplicated frozen literals, `send` vs `__send__`, `report(job, nil)`
niling into the same empty string, and a redundant-return shape.

### The whole project crosses the mutant gate — module_function's unkillable twin
rush-211.8: the first full-project run scored 94.24% (26727 mutations, 1540 alive); applying
the bucket plan landed 95.22% (26546 after ignores, 1268 alive), gate green. The findings
worth keeping. (1) **module_function breeds an unkillable twin**: it defines every method
twice, and while specs call the singleton copy, mutant mutates the instance copy — no test
can ever fail. Signals scored 3.5% purely from this artifact; explicit `def self.` methods
took it to 96.5% (with a description() spec riding along). (2) **:nocov: and mutant-ignore
are the same boundary**: the ten process-boundary wrappers (SystemCalls fork/exit!/kill/
trap_signal/edit_line, the runners' spawn_child/run_child, start_stage) are now matcher
ignores with the rationale written into .mutant.yml — their proof lives in the subprocess
specs, the differential corpus and the pty smokes, all invisible to in-process mutation.
(3) **equal?-mutants hide behind frozen-literal deduplication**: `name != 'LINENO'` mutated
to `!name.equal?('LINENO')` survived because the spec's literal and the lib's literal are
the same deduplicated object; the spec now passes `'LINENO'.dup` — the shape of real user
input. (4) **A masked side effect needs a second act to observe**: unset dropping the export
mark was invisible because exported() slices @vars (the deleted name vanishes either way) —
only reassigning after unset tells; likewise declare_local_operand as a no-op survived a
spec that checked scope restoration but never that the local took effect inside it.
Environment 80.1%→98.0%, ShellVariables 71.7%→97.8%. What remains alive is the catalogued
tail: bucket 3 (differential-covered but unit-thin classes — trap_runner 128, invocation
123, pipeline_runner 72, shell_state 65: their oracle runs rush in subprocesses mutant
cannot see) plus per-file equivalents; porting corpus lessons into unit specs is filed as
backlog, not debt the gate hides.

### Bucket 3 falls — corpus lessons become unit specs, and mutant finds `sh -`
rush-211.9 ported the dash-corpus-proven behaviors of the six unit-thin classes into direct
specs, taking the full project from 95.22% to 96.84% (839 alive of 26553). Per-file:
trap_runner 68.4→96.5, invocation 82.1→99.5, shell_state 71.7→98.7, getopts_state 77.5→95.3,
pipeline_runner 83.3→97.0, parser_support 85.2→98.3. The transferable lessons. (1) **Mutant's
test selection follows the describe constant**: the whole EXIT-trap machinery was guarded by
executor_spec and the differential corpus — invisible for TrapRunner subjects; the same
behaviors asserted in trap_runner_spec killed 100+ mutants without new knowledge, just new
placement. (2) **In-process session runs port differential lessons cheaply**: Invocation's
state/startup wiring became observable by running whole sessions on the fake — $0/$1/$$
through -c, login profiles from a provided /etc/profile, the ENV file only when interactive.
(3) **Structural AST assertions let nil-branch mutants live**: parser_support_spec checked
node classes and item counts, so make_if with a nil branch or a case item with nil patterns
survived; executing the built AST (if/elif/else, case alternation, loop bodies) is what
kills them. (4) A state machine with public cursors (GetoptsState) wants direct stepping
specs, not just its builtin's. And mutation pressure paid off with a second real bug: **rush
opened a file named `-`** where POSIX and dash consume a lone `-` like `--` (`echo 'echo hi'
| sh -` failed with status 2) — fixed in InvocationFlags, pinned by unit and differential
lines. Exit-trap masking rides as a bonus lesson: run_exit_trap publishes the terminating
code as $?, so exiting_status mutants hid until the action changed $? before a bare exit
('false; exit').

### Phase 6 opens: `set -m` lands off-tty — the flag, the ignore, and the groups
rush-mv8 unfroze, and its recorded design risk dissolved on contact: the phase-5 JobTable
already IS the single waitpid owner (every synchronous wait routes through jobs.await /
wait_for; foreign statuses stash), so rush-mv8.1 closed by audit with no code. The
consequence is architectural: no SIGCHLD self-pipe reaper will ever be needed — pre-prompt
notifications can poll WNOHANG at prompt time exactly like dash's showjobs, and WUNTRACED
(mv8.4) is a flag change inside the one owner.

The slice itself was carried by an oracle discovery: **dash 0.5.13 runs monitor mode
without a terminal**. Non-interactive `set -m` is silent and fully real off-tty — every
forked job gets its own process group — while the tty dance is interactive-only ("can't
access tty; job control turned off", flag dropped, at startup and runtime alike). That
made almost the whole slice pinnable by the ordinary differential corpus, no pty needed.
Probing lessons: (1) **EV_EXIT lies to probes** — a tail-position command execs in place,
so "the single command shares the shell's group" was an artifact until a trailing `true`
forced the fork; re-probed, every forked job (background list, pipeline with the first
stage as leader, subshell, single external command) groups, while command substitution and
anything inside a forked child never does (dash's rootshell guard). (2) Only SIGTSTP gets
the shell-side ignore non-interactively — TTOU/TTIN still stop the shell (probed; the
interactive trio arrives with the terminal in mv8.3).

Implementation fell out of existing seams. The monitor-TSTP disposition is *exactly* the
interactive-signals base-disposition model: a user trap beats it in either order, `trap -`
restores the ignore rather than the OS default, `set +m` restores the default, forked
children drop it, exec'd children never see it (handler block, not SIG_IGN) — all probed,
all landed as one TrapRunner#set_base seam (nil removes). JobControl is a stateless policy
view (Executor builds it on demand); the root-shell bit lives in JobTable#root, flipped by
the same clear_for_subshell that already marks forked children. Grouping is
SystemCalls#fork_grouped — the double setpgid on both sides of the fork, where POSIX's
"pgid 0 means the pid itself" lets the kernel do the leader/joiner defaulting with no
branches — plus `pgroup: true` on the spawn path (External), which is the same dance done
kernel-side. POSIX 2.9.3.1/2.11 flip under -m: background jobs keep default SIGINT
(st=130, dash-verified) and keep the shell's stdin (no /dev/null); BackgroundRunner#isolate
reads monitored? before enter_subshell switches it off. Corpus technique: pgid predicates
compare group equality (`same`/`diff`/`grouped`/`own`) so no nondeterministic pid ever
prints, and the TSTP lines run under Timeout because a broken disposition STOPS the shell —
a hang, not a failure. Stopped-foreground lines (dash reports 148 via WUNTRACED) stay out
of the corpus until mv8.4: rush would block today. Lint pressure earned its keep twice:
reek's ControlParameter split toggle(bool) into enable/disable, and FeatureEnvy pushed the
setpgid choreography out of the policy into SystemCalls::ProcessControl — which then
naturally absorbed waitpid2/poll_child as the reaping+grouping syscall cluster.

### The terminal changes hands: tcsetpgrp lands on IO#ioctl, and `-i` now implies `-m`
rush-mv8.3, the slice the epic was really about: under monitor mode every foreground job's
process group owns the controlling terminal for the length of its run, and the shell takes
it back afterwards. Probing dash 0.5.13 under a pty (PTY.spawn driving `dash -i`) settled
four questions the last slice left open — and corrected one of its guesses. (1) **Interactive
dash defaults monitor on**: `$-` on a tty reads `smi` (options.c: an unset mflag resolves to
iflag), so rush's Invocation now defaults :monitor to interactive? — which also means
`rush -i` off-tty now *warns* "can't access tty; job control turned off" exactly like dash,
a fidelity fix the old cli specs had pinned the absence of. (2) **The "interactive trio" is
really a duo**: with the terminal in hand dash ignores TSTP and TTOU, but TTIN keeps the OS
default everywhere — `kill -TTIN $$` stops even an interactive -m dash ("Stopped (tty
input)"); that default is load-bearing, it is what parks a background-started shell in
setjobctl's killpg(0, SIGTTIN) wait-until-foreground loop. (3) **The tty dance is gated on
tty access, not interactivity**: non-interactive `dash -m -c` on a pty acquires the
terminal, self-leaders (pid==pgid, sid elsewhere — probed via ps -o pid=,pgid=,sid=), hands
the tty to each foreground job and ignores TSTP/TTOU; interactivity only decides whether a
missing tty is an error. (4) **`set +m` really restores**: TSTP and TTOU return to SIG_DFL
(both stop the shell again), the terminal goes back to the group that owned it at
acquisition, and the shell rejoins that group.

A probing lesson that cost a round: **stop signals sent to an orphaned process group are
discarded by the kernel**, and PTY.spawn makes the child a session leader whose group is
always orphaned — the first TSTP/TTOU probes answered "alive" for *any* disposition. Wrap
the shell (`sh -c 'dash -i; ...'`) so its parent lives in the same session, and the truth
comes out; the smoke inherits the same wrapper.

Implementation: Ruby exposes no tcsetpgrp, so SystemCalls grows tcgetpgrp/tcsetpgrp over
IO#ioctl with TIOCGPGRP/TIOCSPGRP keyed on host_os (asm-generic 0x540F/0x5410 on Linux, the
sizeof-encoded 0x40047477/0x80047476 on darwin/BSD; an unmatched Unix gets nil and job
control degrades to grouping-only — the epic's Fiddle-into-libc fallback was judged not
worth a dependency for platforms rush cannot test). tcsetpgrp holds TTOU ignored (real
SIG_IGN, scoped) for the call: the reclaim always runs from a background group, where a
caught handler would EINTR the ioctl and a default disposition would stop the shell.
Terminal (a new class) owns the dance: Terminal.acquire is dash's setjobctl(1) — open
/dev/tty or a dup of the first standard tty fd, tcgetpgrp with the TTIN wait loop, remember
`initial`, setpgid(0,0), take the tty — while give/reclaim/while_given/restore are
forkchild's FORK_FG xtcsetpgrp, waitforjob's take-back and setjobctl(0). The handover is
double-sided like the setpgid dance: fork-path leaders tcsetpgrp themselves child-side
before the body runs (grouped_child), and JobControl#foreground gives parent-side right
before the wait — which is the only side the spawn path has, so External's race window is
the µs between spawn returning and one ioctl, against the child's whole execve. Durable
state condensed into JobTable::Control (root-shell bit + held terminal, dropped together by
clear_for_subshell); reek's ivar budget forced that grouping and it reads better than the
two loose fields it replaced. FakeSystemCalls models terminal ownership (open_tty/
tcgetpgrp/tcsetpgrp recording handovers, a foreground queue for the TTIN loop), so every
choreography line is unit-pinned.

Verified: full rake green (2012 specs, 99.93/99.56 coverage), and a new differential pty
smoke in the Docker gate (docker/job-control-smoke.rb) that drives rush -i and dash -i
through the same session and compares extracted *pictures* — monitor flags, self-leadering,
job-owns-tty for spawn/pipeline/subshell (ps -o pgid=,tpgid= equality predicates, no raw
pids), tty-stays-home for cmdsub/background, TSTP+TTOU survival, set +m rejoin, exit
status — rush's picture is byte-for-byte dash's. Corpus untouched: everything here needs a
tty, and the off-tty behaviour was pinned last slice.

Docker-gate postscript: the container needed procps (the smoke's pgid/tpgid probes are ps
calls), and running the gate surfaced a pre-existing container-only failure unrelated to
this slice — two real_shell_spec inherited-fd examples see their writes reversed inside the
ruby:4.0.5-slim image while passing natively; reproduced on the previous main tip in the
same image, filed as rush-erq. The job-control smoke itself runs green inside the container.

### ^Z lands: WUNTRACED waits, the Stopped state, and the exit guard
rush-mv8.4: under monitor mode every blocking wait goes through waitpid2(…, WUNTRACED)
(SystemCalls#wait_stoppable, paired with a WNOHANG|WUNTRACED poll_stopped), so a foreground
job the terminal — or a kill — stops hands control back to the shell instead of hanging it.
The probes rewrote two assumptions. (1) **WUNTRACED is keyed on mflag, not the terminal**:
non-interactive `dash -m -c 'sleep 6; …'` on a pty continues past a stopped job with
$? = 148, and plain off-tty `set -m; sh -c 'kill -TSTP $$'` does the same — which makes
almost the whole slice pinnable by the ordinary differential corpus, no pty needed
(jc-stop-001..008). (2) **The stopped-jobs exit guard is not interactive-only**: batch dash
prints "You have stopped jobs." and refuses the first exit too (the refused exit answers
$? = 0 and the script carries on); what IS interactive-only is the re-arm — dash's
job_warning decrements once per cmdloop turn, so an exit repeated as the very next command
goes through while anything later re-arms the warning, and a batch shell (nothing ticks)
warns exactly once. Both live in JobTable::Control#warn_exit?/tick_warning with the Repl
ticking per turn, dash's globals to the letter.

The state model: Status learns stopsig (128+sig as the code, the signal riding along), and
a stopped wait parks the WHOLE job — JobControl#foreground adopts it into the table as one
entry, leader pid plus every pipeline member (Job grows members for mv8.5's fg/bg) — where
jobs/wait/kill/%ids find it. Stopped entries answer `wait %1` with 148 immediately and
repeatably, keep their slot when displayed (only finished jobs are freed — probed), and a
later reap of the real death flips them Done — the corpus pins the 137-after-kill dance.
The single-owner strategy needed one adjustment: a stopped job still counts as alive for
the waitpid(-1) decision, since its death arrives asynchronously. Mixed pipelines follow
dash's getstatus: `stopped | exit5` answers 5 while the job parks Stopped (probed both
orders), expressed as Status#with_stop riding any stage's stop signal onto the verdict.
The jobs listing prints the glibc strsignal vocabulary — Stopped, Stopped (signal),
Stopped (tty input/output) — from a Signals.stop_description table.

Corpus lessons. **A `jobs | sed` projection is unusable**: dash's forked pipeline stage
still lists the parent's jobs while rush's clear_for_subshell empties the table — a real,
previously invisible divergence (filed rush-r6i, bundled with mv8.6's rendering work);
`jobs > file` redirects (no fork) project the state column deterministically instead, sed
stripping the command-text column that arrives with mv8.6. **Pipeline stops stay out of
the off-tty corpus**: `sh -c 'kill -TSTP $$'` inside a pipeline stops only the grandchild,
and rush's stage supervisor — which dash EV_EXIT-execs away, the recorded mv8.7
divergence — then blocks in a non-WUNTRACED wait (its subshell cleared the monitor bit),
exactly as dash's own `{ …; }`-wrapped stage would; the real whole-group ^Z, where the
supervisors stop too and the WUNTRACED wait settles, is the pty smoke's job.

The smoke grew the ^Z act (sleep 100, raw \x1a, ZST/ZJOBS/ZALIVE/ZW markers) and two
harness lessons worth keeping: the writer must not outrun the shell — a slow interpreter
start let the ^Z land while rush still chewed the queued backlog, stopping the wrong job,
so marker-wait {sync:} barriers now pace the script — and the kill-then-wait probe must be
ONE line: an intervening prompt lets dash's pre-prompt notifier report-and-free the killed
entry (mv8.6 behaviour) and `wait %%` answers "No current job" instead of 137. Lint
pressure again shaped the design: reek's ivar budget pushed the exit-warning window into
Control and Job onto a members-array (pid = its head), ControlParameter split the polls
into a poll_child/poll_stopped pair mirroring waitpid2/wait_stoppable, and FeatureEnvy
moved the state column's vocabulary onto Job#display_state — each a better home than the
flag or helper it replaced.

Verified: full rake green (2056 specs, 99.97%/99.79%), the extended differential corpus
(8 jc-stop lines) matches dash 0.5.13, and the pty smoke — including the ^Z act — passes
natively; ^Z on a pipeline is exercised there by the whole-group stop.

### fg and bg come alive — and the whole resume dance fits off-tty
rush-mv8.5 replaced the phase-5 stubs. The probing surprise that shaped the slice: **fg
needs no terminal**. SIGCONT plus a WUNTRACED wait is the entire choreography off-tty, so
thirteen jc-fgbg corpus lines pin nearly everything differentially — fg resuming a
self-stopped job (status 0, entry freed — dash frees what it fg-waited), fg carrying the
job's exit code (probed 7), bg resuming into the background (`wait` then answers 0), both
on already-running jobs, multiple operands looping with the last status winning (probed:
`fg %1 %2` foregrounds both in turn), a second ^Z re-parking under the same number with
$? = 148, and fg on a dead-but-remembered entry answering its recorded 137 from memory.
fg's stdout line — dash prints the job's command text — hides behind >/dev/null until the
text column lands (mv8.6); rush prints an empty placeholder line, bg prints "[n]".

The refusal is a per-job bit, not a mode: dash stamps each jobtab entry with the jobctl in
force when it was created, so a job born under -m is resumable after `set +m`, and a job
born without never becomes resumable however hard you set -m (probed both directions,
corpus-pinned). That bit is Job#controlled? — an :origin symbol stamped by
Control#origin — and both refusal messages stay byte-identical to the phase-5 stubs the
new builtins replaced (fg/bg resolve first, then refuse, dash's operand-aborting sh_error
shape through the same JobError path as a bad %id).

Fg's wait reuses the whole mv8.3/8.4 machinery: JobControl#foreground hands the terminal
over and adopts a re-stop, JobTable#settle_members waits every member — the leader through
its entry (harvest), the rest through the stash-aware await — and PipelineStatuses picks
the verdict, so a resumed pipeline behaves exactly like a fresh foreground one. Design
churn worth recording: reek chased the resume choreography to its right home — the
mark-running-and-SIGCONT pair became Job#continue(system) (FeatureEnvy kept flagging every
helper that touched `job` twice), and Job now stores a rush Status instead of the raw
Process::Status, which required Status to learn termsig (the jobs listing must tell
Killed from Done(137) — information the 128+signal code alone destroys) and dissolved
three nil-check smells in one move. The pty smoke grew the resume act: ^Z, bg, its wait
settling 0, another ^Z, fg blocking through the job's remaining run, the session carrying
on — dash and rush byte-for-byte on the extracted picture.

Verified: full rake green (2069 specs, 99.95%/99.58%), differential job-control corpus now
49 lines, pty smoke green natively and in the container.

### The jobs column speaks: cmdtxt lands, and the prompt announces the changes
rush-mv8.6, the epic's last open slice. The mv8.2 note "dash keeps text only under a tty"
dissolved under better probes: the command-text column is keyed on the per-job jobctl bit —
controlled jobs print their text on and off a tty — which made the whole renderer
differentially testable off-tty (`set -m; CMD & jobs`): twenty jc-text corpus lines pin
CommandText byte-for-byte against the oracle, and the fg/bg echo lines lost their /dev/null
projections. dash's cmdtxt canon, probed shape by shape: parameters always braced (${T},
"${@}", ${T:-9} with the raw default source), command substitutions and here-documents
elided to $(...) and <<..., every redirect fd explicit (1>/dev/null, 0<f), assignments
dropped from commands with words — an assignment-only job renders as `set`, a genuine dash
quirk — group braces dropped, elif re-spelled as nested else-if, `!` prefixed without a
space, case alternation truncated to the first pattern, and the implicit for-list spelled
out as in "${@}". Words rebuild from rush's segments: consecutive quoted segments share one
pair of double quotes with \\ " $ ` escaped — each segment kind canonicalises itself
(WordSegment#canon, ParamRef#canon), which is also where reek pushed the dispatch. Known
un-replicated nuances, journal-only: dash distinguishes quoting origins rush's lexer
normalises (a dquoted \$ prints unescaped where a squoted $ prints \$ — rush always
escapes), renders parse-time tilde expansion results, and prints backquote substitutions
with their body; none is reachable from the corpus shapes chosen.

The text is the jobctl stamp itself: Job::Identity keeps nil outside monitor mode — exactly
dash, where cmdtext exists only for jobctl jobs — so Job#controlled? reads the text's
presence and the mv8.5 origin symbol dissolved. JobControl#job_text gates the rendering;
runners pass it at launch (BackgroundRunner), adoption (pipeline/subshell/external — the
external can't see the AST, so CommandRunner renders and External#call carries it), and fg
re-parks with the job's own text.

Notifications: dash's cmdloop runs showjobs(SHOW_CHANGED) before each PS1 — probed: the
lines go to stderr with the prompts, only under monitor mode (set +m silences them, and
nothing prints off-tty), no launch announcement (unlike bash), Done/Stopped/Killed flavours
in the same showjob format as the jobs listing, a change collected by the wait builtin
still announces later, and CONT is never noticed (no WCONTINUED — the display stays
Stopped until a real state change). Landed as a changed bit on Job (set by finish/stop,
cleared by display, by the notifier, and by bg's resume — bg's own "[n] text" line is its
announcement), JobTable#announce_changed draining it pre-prompt from the Repl, and
JobReport sharing the line renderer with the jobs builtin. The exit-refusal predicate
moved into the Exit builtin on the way (reek's line budgets kept every class at its cap —
the fifth ivar Job needed became the Identity bundle).

Probed and deliberately deferred: dash's printsignal — the bare "Killed"/"Terminated"
stderr line when a job dies by signal (any reap path, INT/PIPE excluded, "(core dumped)"
suffixed, suppressed by the command's own 2>/dev/null) — is independent of job control
entirely and invisible to the corpus; filed as rush-hkp rather than smuggled in here.

Verified: full rake green (2140 specs, 99.93%/99.39%), differential job-control corpus 72
lines, the pty smoke now also asserts the pre-prompt Stopped/Killed announcements with
their command text — dash and rush byte-for-byte, natively and in the container.

### The mutant gate after the epic: two mechanical blind spots and a real tail
The first full-project mutant run after rush-mv8 scored 92.70% against the 95% gate (29598
mutations, 2160 alive) — and the post-mortem is more instructive than the number. Two
thirds of the drop was mutant-blindness, not test weakness. (1) **Matcher names follow the
defining module**: .mutant.yml ignored Rush::SystemCalls#tcsetpgrp, but mutant identifies
mixin methods as Rush::SystemCalls::ProcessControl#tcsetpgrp — the whole :nocov: syscall
cluster (275 mutations) ran un-ignored and untested. (2) **The rush-211.9 describe-constant
lesson struck again**, this time from the other side: spec/rush/builtins/job_resume_spec.rb
described a STRING ('fg and bg'), so mutant selected no meaningful tests for
Builtins::JobResume/Fg/Bg — 258 alive at 2-3% kill rates over code with real behavioural
specs. Splitting into three constant-keyed files (JobResume base behaviours exercised
through the concrete subclasses) took the trio to 95%+ with barely a new assertion. The
same re-keying applied to the notifications spec (now describe Rush::Repl).

The honest third: the epic's new classes were behaviourally covered but mutant-thin —
Job 43% killed (display_state strings, the changed lifecycle, report, continue), Terminal
26% (the whole acquire dance was only reachable through job_control_spec, the wrong
constant), Status#with_stop, LiteralSegment#canon (covered only via command_text_spec —
wrong constant again), JobControl#launch_background (tested via background_runner_spec —
wrong constant), JobTable#settle_members/announce_changed (via the string-described
specs). Direct, constant-keyed specs — the display_state matrix, the .acquire/.while_held
cluster, stopsig-across-states, job_control_supported? across host_os values, adopt
re-parking idempotence — brought the full project to 96.49% (1031 alive), gate green. The
meta-lesson consolidated: with mutant in the toolchain, WHERE a behaviour is asserted
matters as much as THAT it is asserted — every new class wants its own constant-keyed
spec file from birth, and mixin ignores must name the module, not the includer.

### Bare set -o / set +o: the settings listings land (rush-53j)
Bare `set -o` now prints dash's "Current option settings" table (name ljust-16, then
on/off) and bare `set +o` the `set -o name`/`set +o name` re-input form (POSIX XCU set:
-o unspecified format — so dash's; +o must reproduce the settings on re-input). Both render
from one NAMES vocabulary on Options in dash's listing order, including the invocation-only
interactive/stdin flags dash also lists; their re-input lines are silently-ignored unknowns
to set, so the round-trip stays lossless. Probed: dash accepts `set +o interactive` (rc 0),
the +o round-trip restores flags through eval (`set -u; s=$(set +o); set +u; eval "$s"` puts
u back in $-), both bare forms exit 0, and the name column is exactly 16 wide (cat -A). The
corpus pins shared rows byte-exact via grep projections — full listings differ by design
(dash lists 18 options, rush its 11) — plus the eval round-trip and rc lines. One quirk died
on the way: bare trailing `-o` used to report "2 args consumed", walking the parse index past
the end, where positionals() then emptied the parameters via args.drop — it now consumes
itself and leaves them alone (dash agrees). Reek shaped the seam twice: ControlParameter
pushed the -/+ branch into apply_long, where sign is dual-used like the toggle precedent,
and RepeatedConditional (first on?(option) ×3, then the renamed block param — reek counts
same-named locals across methods) dissolved once the render helper takes on_form/off_form
format strings and picks between them exactly once.

### printsignal lands: the reap funnels report signal deaths like dash (rush-hkp)
The probe matrix refined the epic-close notes in three ways. (1) dash's real rule is
per-process: ANY dash process's foreground wait prints strsignal(sig) for a reaped child
killed by a signal other than INT/PIPE ("Killed", "Terminated", "User defined signal 1",
" (core dumped)" suffixed on WCOREDUMP) — fg simple commands, pipeline stages, cmdsub
children, subshells, functions. (2) The wait builtin prints only for pid/%id operands; a
bare `wait` NEVER prints (probed: `kill -KILL $!; wait` is silent, `wait $!` says Killed) —
the epic note's "wait-builtin reaps print" had conflated the pre-prompt notification line
with printsignal. (3) Where the message lands follows dash's redirect mechanics: a simple
command's own 2>/dev/null suppresses it (dash applies simple-command redirects in the
parent, so the parent's printsignal writes into them), while a pipeline stage's or a
cmdsub body's own 2>/dev/null does NOT (EV_EXIT execs those away, so the main shell — fd2
unredirected — is the reaper); group redirects suppress everywhere.

Landed as SignalReport (Status gains the WCOREDUMP bit, nil-defaulted after reek's
BooleanParameter pushed it to stopsig/termsig-style absence semantics) called at six reap
sites: External (onto the command's IoTable stderr — the simple-command suppression falls
out for free), PipelineRunner per stage, SubshellRunner, CommandSubstitution and Fg#settle
(shell stderr), and Wait#awaited for operands only. rush's extra fork layer makes the
supervisor's own External the printer for in-stage deaths — its inherited fd2 IS the shell
stderr, so the observable matches dash — and since a supervisor exit!s 128+n, the outer
await sees no termsig and never double-prints. Divergences, all EV_EXIT-family
(journal-only, stderr-invisible to the corpus): a bg SIMPLE command whose process kills
itself prints from rush's bg child where dash is silent (dash's compound bg `{ ...; } &`
prints identically to rush — probed); a stage/cmdsub body's own 2>/dev/null suppresses in
rush where dash prints (rush honors the command's redirect — arguably kinder). Corpus
trick worth keeping: `cmd 2>file; echo rc=$?; cat file` routes the report into the
stdout comparison, so eight printsignal lines pin TERM/USR1/SEGV/INT-silence/stage/
cmdsub/wait-by-pid/bare-wait differentially despite the stderr-ignoring harness. The
glibc strsignal vocabulary grew USR1/USR2/BUS/TRAP spellings; instance_doubles of
Process::Status all needed coredump? stubbed once Status.of started reading it.

Verified: full rake green (2235 specs, 99.98%/99.6%), 8 new differential corpus lines,
the pty smoke passes natively byte-for-byte (its kill+wait act now exercises the
printsignal line in both shells alike).

### The container gate turns green: buffered fd wrappers and same-session strays (rush-erq)
Two container-only failure families, two environment truths. **The reordered
inherited-fd writes** were never about the container's fs: every `n>&9` evaluation wraps
fd 9 in a fresh IO.for_fd, and each wrapper carries its own userspace buffer, flushed at
process exit in GC order — Debian's Ruby happened to flush them reversed, native Ruby in
order, both by luck. The native proof needed no container at all: `echo one >&9; cat file`
showed cat an EMPTY file (the bytes sat in the wrapper) where dash, which writes straight
to the fd, showed the line. inherited_fd now sets sync=true on the wrapper — writes land
immediately, in command order, everywhere; a real_shell example pins the mid-script
visibility.

**The jc-stop timeouts** (three corpus lines exiting with a live stopped job) exposed a
false comfort in the corpus comment: "the orphaned stopped children die on their own
(kernel HUP+CONT)". True natively — the dying shell's stopped child re-parents to init in
ANOTHER session, the process group orphans, POSIX's HUP+CONT reaps it. In a container the
child lands on a same-session pid 1, the group never orphans, and the stray stopped sh
holds the Open3 capture pipes open forever — BOTH shells hang the harness identically
(dash -c by hand leaves the same T-state stray; probed). Fix at the harness, not the
corpus: the stopped-jobs block runs both shells under setsid, restoring the native
re-parent-outside-the-session topology, so the corpus semantics (exit refusal, wait
answers, jobs listings) stay pinned unchanged. Meta-lesson: any corpus shape that exits
leaving a stopped child is a session-topology bet — make the session explicit.

Verified: native rake fully green (2237), and bin/test-in-docker exits 0 end-to-end —
in-container rake 2237/0 plus all three smokes (syscall, Reline pty, job-control pty).
The two prior real_shell failures and the three jc-stop timeouts reproduce deterministically
at c86ffea (pre-slice worktree, same image), confirming both families pre-existed.

### The subshell job table becomes a display copy — and the oracles disagree with themselves (rush-r6i)
Re-probing dissolved the bead's original premise twice over. dash's forked children do
NOT list the parent's jobs: `(jobs; echo x); echo tail` prints nothing, and a brace-group
pipeline stage `{ jobs; ...; } | cat` prints nothing while numbering its own new jobs from
[1] — the shapes that DO list (`jobs | cat`, `jobs > f` in `( )` single-command subshells,
`$(jobs -p)`) are the ones dash never really forks (the EV_EXIT/no-fork family, again
lying to probes). Meanwhile %id resolution refuses everywhere: the same dash stage that
lists [1] answers "No such job: %1" to wait/kill (rc=2). bash is inconsistent the other
way around (cmdsub copies, explicit subshells do not, `jobs -p` in a stage prints nothing
where plain `jobs` lists). The standard, unlike either oracle, is uniform: 2.12's shell
execution environment includes "process IDs of the last commands in asynchronous lists",
a subshell environment is "a duplicate of the shell environment", and the jobs page
blesses $(jobs -p) as THE portable idiom — while the wait page normatively scopes known
pids to "the current shell execution environment". So rush now implements the uniform
reading: enter_subshell demotes entries to inherited display copies (Job#inherit) —
listable by jobs/jobs -p with their numbers and marks intact — while Job#harvest answers
nil for them (wait: 127), JobSpec#live refuses them (%id: No such job), and reap_one's
liveness test skips them so a child's foreground waits still target directly. The payoff
is the acceptance line: `wait $(jobs -p)` now returns the job's real status (rc=7) like
both oracles, because the substitution child can still render the parent's pids. Corpus
pins the shapes where dash agrees (jobs|cat with and without -m, jobs -p|wc, stage wait %1
rc=2, three wait $(jobs -p) flavours); the dash-empty forked shapes stay out — the letter
of 2.12 beats the fork-topology accidents (project rule). Two rubocop ClassLength caps
forced honest moves: the statusfmt vocabulary (display_state) migrated from Job to
JobReport.state — the renderer was its real home, and JobReport finally got its own
constant-keyed spec (the 13f lesson applied preemptively) — and the inherited refusal
went INTO Job#harvest rather than a second nil-check at the table. Divergence noted: rush
children number new jobs above the inherited copies where dash restarts at [1] (its table
is empty); unreachable differentially since dash lists nothing there.

Verified: full rake green (2256 specs, 99.98%/99.6%), 7 new differential corpus lines,
the seven-shape probe matrix byte-for-byte vs dash, pty smoke green.

### The stage stop relay: a stopped pipeline member no longer wedges the shell (rush-l4o)
The bug that left 7-hour orphans on the box: off-tty `set -m; sh -c 'exit 5' | sh -c
'kill -TSTP $$'` hung rush forever — the stage supervisor (the fork layer dash EV_EXIT-
execs away) waited non-WUNTRACED on its stopped grandchild while the main shell waited on
the supervisor. Probing redrew the oracle map first: dash answers st:148 ONLY on shapes it
never really forks (simple-command stages, single-command subshells — EV_EXIT reaching
even through `{ ... }` braces); on honestly-forked compound stages dash hangs exactly like
rush did, and bash hangs on its wrapped form too. Even the journal's own mv8.4 claim
("dash's brace-wrapped stage would block the same way") proved half-wrong — the braces
alone don't defeat EV_EXIT; a second command inside does. And the l4o acceptance idea
"external kill -STOP of one member must not wedge" fell to the oracle as well: a job is
stopped only when EVERY member stops, so a single externally-stopped member leaves both
dash and rush legitimately waiting (probed: both hang; parity, not defect).

The fix makes the supervisor a transparent job member. Control's monitor bit grew into a
three-valued stops mode (:default/:monitor/:relay — same ivar count, the reek budget
holds): PipelineRunner#run_stage arms the relay child-side BEFORE the body's subshell
reset, while the parent's monitor bit is still readable, and fork_child preserves an
armed relay so stops bubble out of nested forks. The reap loop (JobTable#reap_raw) then
waits WUNTRACED whenever stops are visible (monitor OR relay) and, on reaping the
target's stop, hands it to StopRelay: default disposition first (the -m parent left
TSTP/TTOU ignored; SIGSTOP takes none and cannot be trapped — the fake's EINVAL caught
that), then the same signal onto the supervisor itself. The main shell's WUNTRACED wait
sees the member stop, parks the job with the true stopsig ($?=148, dash-exact), and
fg/bg's SIGCONT to the group resumes supervisor and grandchild together — the relay loop
re-waits the same target and the resumed job settles normally. Five jc-stop corpus lines
now pin what "stayed out of the corpus" since mv8.4: both stop orders (st:148 / st:5 via
with_stop), both-stages-stopped, and the full bg- and fg-resume dances, byte-for-byte
against dash under the setsid runners. Compound-stage stops stay out and are the recorded
divergence: dash and bash hang there, rush's relay answers 148 — the hang serves nobody,
and the whole-job model (2.12) sides with answering. Two rubocop ClassLength caps pushed
the relay into its own StopRelay module (constant-keyed spec from birth) and dissolved a
one-line JobControl facade in favour of the existing executor.jobs.control seam.

Verified: full rake green (2270 specs, 99.98%/99.6%), the 77-line jc corpus including the
five new stop lines, pty smoke byte-for-byte, container gate green end-to-end, and the
original hung-probe shape returns promptly with the job parked and killable.

### flay and flog join the gate — rubycritic evaluated and declined (rush-apz filed)
The rubycritic question answered itself on inspection: it is not a reek alternative but a
wrapper AROUND reek 6.5 (plus flog, flay and git churn), collapsed into one GPA gated only
by --minimum-score — a new smell in a small file barely moves the aggregate where the
current reek task fails the build outright, and the churn term punishes files for being
edited, not for getting worse. It also drags its own simplecov in, which picks up our
.simplecov and stomps coverage/ with a 0% report. Evaluated live (5.0.0, maintained,
3 seconds over lib/ on Ruby 4.0.5) and declined; what it genuinely added — flay's
structural-duplication view — landed directly instead. fasterer was probed the same
morning and declined too: dormant since early 2024, rules frozen in the Ruby 2.x era,
and its niche already covered by rubocop-performance, which (surprise of the day) has
been a plugin in .rubocop.yml all along — it was Performance/RedundantBlockCall that
reshaped the Options renderer in slice 14a.

So the gate grew two baseline-pinned ratchets in tasks/complexity.rake, mirroring the
mutant:check pattern: flay (total duplication mass over lib+exe minus the generated
parser, threshold 2016 = today's measurement) and flog (worst single method, cap 26.0
over today's 25.9 — ShellState#initialize, the known excluded coordinator). Thresholds
only go down; paying debt lowers them. What flay actually found — and reek structurally
cannot see — is one IDENTICAL seven-node save/yield/restore cluster (errexit_context ×2,
executor ×2, loop_nesting, shell_state ×2, mass 833) plus two small clusters; filed as
rush-apz rather than fixed inline, since extracting the seam is its own design decision.
Wiring note: a second top-level module in the Rakefile trips Style/OneClassPerFile — the
gates live in tasks/complexity.rake, loaded like compile.rake and docker.rake.

### The flay debt paid: delegation double-sigs and real duplication, separated (rush-apz)
The "seven-node save/yield/restore cluster" turned out to be a misreading worth
recording: flay's IDENTICAL :iter nodes were not the method bodies but the Sorbet
`sig do ... end` blocks above them — seven textually identical generic block sigs
(`type_parameters(:U)`, block in, block's value out). Sorbet demands a literal sig
block per `def` — a generic sig cannot be aliased (`T.type_alias` takes no type
parameters) and a metaprogrammed sig is invisible to srb — so two methods with the
same block-wrapping shape ALWAYS flay identically. The cluster split cleanly into
the forced and the earned. Earned: Executor#tested/#untested re-exported
ErrexitContext's wrappers with the full sig copied (two layers of delegation for
one flag swap — ErrexitContext#scoped went public with the tested/untested pair
folded into the facade), and Executor#with_redirects duplicated RedirectScope's
whole four-line sig to re-export it (the reader seam executor.redirect_scope
replaced it, matching the existing executor.state.loops style; the default base
moved into RedirectScope). Forced: the five survivors — tested, untested,
LoopNesting#without, with_loop, preserve_status — are five genuinely distinct
scoped-state operations, one literal sig each, journaled here as idiomatic and
noted in tasks/complexity.rake.

The riding-along clusters were honest duplication and produced real seams: the
@literal/@segments accumulator copied across WordScanner, HeredocBody and
ParamText became SegmentBuffer (push closes the pending literal run as an
unquoted segment, #word closes it once more and builds the AST::Word — the three
scanners lost their build/push/flush triplets), and break/continue collapsed into
a LoopJump template (validate level >= 1 even loopless, $?=0 before unwinding,
raise the subclass's LoopControl signal clamped to the nesting depth).
FLAY_THRESHOLD ratcheted 2016 -> 1170; flog untouched. Verified: full rake green,
differential corpus intact.

### File.new is the honest spelling for a caller-owned handle (rush-oks)
The gate's only Style/FileOpen disable guarded open_file, where the auto-closing
block form really would be wrong: a redirection's file must outlive the call,
and close_redirect owns the close. The resolution was already in the language:
File.new constructs a handle whose lifetime the caller manages — behaviourally
identical to blockless File.open — and satisfies both Style/FileOpen and
Style/AutoResourceCleanup, so the disable/enable pair dissolved into a one-word
change plus the spec stub following suit. (open_tty's bare open-and-return never
triggered the cop, which flags the chained File.open(...).tap shape; its
ownership story was already documented inline.) First of the six disable-paydown
beads filed after the 14g review of every rubocop suppression in the tree.

### The Executor sheds its facades and the ClassLength disable (rush-6tx)
Executor sat at 112/100 behind the gate's oldest ClassLength disable, and the
overweight was pure re-export: run_exit_trap copied a delegator over the
ALREADY-public trap_runner reader, exitstatus relayed what trap_runner.rb and
shell_parameters.rb were reaching directly as state.last_status.exitstatus all
along, and the errexit trio (tested/untested/exit_on_error) wrapped
ErrexitContext behind a second copy of each generic block sig. All four
dissolved the 14e/14g way — collaborator readers over facade methods: callers
now say executor.trap_runner.run_exit_trap and executor.errexit.tested. The
POSIX vocabulary moved with the dissolution, not against it: tested/untested
live on ErrexitContext again (scoped back to private), so and_or still reads
`executor.errexit.tested { run(left) }`. Flay stayed put at 1170 — the two
generic sigs moved house rather than vanished, and the ×5 identical-sig cluster
just changed one address. Executor is under the cap with room to grow
(succeeds? and the cmd-sub channel stay: composites and owned state, not
facades). AST node specs that spied on the facade to prove "ran tested" now spy
on executor.errexit directly.

### The double-quote sub-language moves out of WordScanner (rush-lfw)
WordScanner carried its ClassLength disable because two scanners lived in one
class: the bare-word walk and the "..." interior, each with its own dispatch
rules (DOUBLE_LITERAL runs, the four escapable specials, the quoted-dollar
fallback). The 14g SegmentBuffer made the cut almost mechanical — the new
DoubleQuoteScanner shares the host's StringScanner and buffer and pushes quoted
segments into the same word under construction. The one genuinely shared rule,
line continuation (whose IncompleteInput behaviour depends on the host's
interactive/terminator mode), stays owned by WordScanner and is injected as a
callback rather than duplicated — the sub-scanner knows THAT a backslash-newline
defers, the host knows WHAT deferring means. Both classes sit under the cap;
the disable is gone; flay unmoved at 1170.
Wiring note: this was the codebase's first `T.proc.void` in a sig, and steep
type-checks sig blocks as plain Ruby against the hand-written sorbet_dsl.rbs
stub — which knew params/returns on ProcBuilder but not void. The stub grows
with first uses; extend it there, not with a Steepfile ignore.

### The optstring becomes a value object; GetoptsParser sheds its disable (rush-37o)
GetoptsParser sat at 109/100 because two POSIX concepts shared one class: the
optstring operand's own semantics (a leading colon selects silent reporting,
a trailing colon marks an argument-taking letter) and the step-parse cursor
choreography. The optstring is now a value object — Optstring owns the
effective letters, derives the GetoptsErrorMode, and answers valid? /
requires_argument?; the parser walks argv against it. Same file, third class:
getopts_parser.rb is the getopts-parsing unit the way GetoptsErrorMode already
established. The parser is well under the cap and the third ClassLength
disable of four is gone.

### The ShellState coordinator slims down; the AbcSize floor is measured, not assumed (rush-ujp)
The double-guarded hotspot — the gate's only AbcSize disable AND the flog
maximum at 25.9 against a 26.0 cap — came down by honest moves only: PPID and
OPTIND seeding folded into one seed_variables step (the variables a POSIX shell
is born with), ShellProcessIds stays whole behind a pids reader instead of
being unpacked into two ivars ($$ readers follow the value object), and the two
stateless views — ShellParameters and FunctionFrame — are built on demand the
way Executor#job_control established, vanishing from the wiring entirely.
AbcSize fell 24.08 -> 17.69 and flog 25.9 -> 19.3, which dethroned the method:
the flog ratchet drops 26.0 -> 19.5 over the new maximum (TestExpr#evaluate,
19.4). The last three AbcSize points were left on the table deliberately: 13
tables wired with zero branches is ~18 from breadth alone, and going lower
means bundling namespaces POSIX keeps distinct (aliases are pre-parse
substitution, not command search — a "Definitions" composite would be
metric-driven, not domain-driven). The disable stays with that arithmetic
written next to it; the bead closes on the measured floor, not the wished-for
zero.

### The NumberConversion amnesty ends: eight excludes become three reasons (rush-qle)
The bulk waiver ("regex-guarded parsers or deliberate zero semantics") hid three
different situations. kill.rb was a stale entry — it had moved to Integer()
long ago and needed nothing. Four files were regex-guarded parsers where the
lenient .to_i added nothing the guard hadn't already promised: numeric_operand,
test's MaybeInteger, $N resolution and signal-number decode now use
Integer(_, 10) — same accepted domain (Kernel#Integer strips the blanks the
guards allow, the sign parses, and the explicit base kills the octal
leading-zero trap), but a future guard/conversion drift now raises instead of
silently parsing garbage as 0. Three files remain excluded, each with its own
one-line contract in .rubocop.yml: Process::Status nil signals pinning to 0
(status.rb), File.size? nil counting as empty (file_tests.rb), and the test
double mirroring the latter. The cop now runs on 173 of 176 files with every
survivor individually justified.
Wiring note: reek's ControlParameter reads `value&.between?(min, ...)` as min
controlling a branch, though the equivalent `cond && value.between?(min, ...)`
never smelled — the csend lowers into the conditional it inspects. The range
check moved into legal_operand?(value, min), where min is plain data and the
caller narrows with T.must; structure, not suppression.

### Flog splits its mandate: constructors to AbcSize, logic to the ratchet (rush-2vh)
TestExpr#evaluate was the last logic method above the ShellState wiring floor —
19.4 from three POSIX structural rules inlined into one dispatcher, exactly
where flog and AbcSize diverge: rubocop scored the same method ~11 because ABC
ignores nesting, while flog charges for branch depth and inline recursion.
Naming the recursive rules (negated?, unwrap) dropped evaluate to 13.6 while
staying the arity table XCU test specifies. A third extraction (binary_first?)
went too far: two args references against one self call is reek's FeatureEnvy,
so the binary-outranks check stayed inline — the smell drew the line between
naming a rule and exiling a condition from its dispatcher. That left both >16
scores on constructors, so the gate's mandate split: flog_max now skips
#initialize lines — wiring breadth is AbcSize's job (cap 15, one documented
exception) — and FLOG_METHOD_MAX ratchets 19.5 -> 16.1 over Getopts#apply at
16.0. Both dimensions got tighter: logic methods lost the 3.4 points of
headroom the wiring floor had been padding them with, and constructors answer
to the stricter of the two meters as before.

### The flog ratchet lands on 16.0 and rests (rush-16y)
The last method above the line, Getopts#apply at 16.0, was doing the two
things its own Result doc names separately — "the variable updates and status
produced by one getopts step" — so the three variable writes moved into
#store(result) and apply kept the reporting and the Status. Worst logic method
is now 15.8 (Read#assign / LoopJump#call), and FLOG_METHOD_MAX pins at a round
16.0 with real headroom for the first time (every earlier cap sat 0.1 over its
measurement). Deliberate stop: the 15.x band below is dense — five methods
within half a point — and each further tenth would cost a full refactor;
squeezing past it is a different day's decision, recorded here so the next
reader knows the plateau is chosen, not forgotten.

### Flay round two: 1170 -> 906, and what stays is named (rush-g9m)
Three squeezes below the journaled sig cluster, each a seam the code had been
hinting at. While/Until were twins down to the :while/:until symbol handed to
LoopRunner — a ConditionLoop base holds the shape the way LoopJump does for
break/continue. Export/Readonly shared their whole call loop, differing only
in which marking ShellVariables applies — a Declare base keeps the loop, the
subclasses keep their one-line declare (the NotImplementedError stub takes
_operand: reek's UnusedParameters is right that a hook stub does not use its
argument). And the anonymous [String, bool, bool] tuple threaded from
Pipeline#field_parts through FieldSplitter into IfsScanner got its name —
Expansion::FieldPart, a T.type_alias documenting text / IFS-splittable /
field-break — which shrank four identical sig nodes below flay's radar while
finally saying what the three booleans mean. Left deliberately: the x5 generic
block sig cluster (Sorbet-forced, journaled at 14g), SimpleCommand's
select-by-type triple (the T.let+each dance is the only shape both type
checkers narrow without casts), and the similar-sig families. FLAY_THRESHOLD
1170 -> 906.
Wiring note: LoopRunner's RBS types its mode as the literal union
:while | :until, so ConditionLoop#kind couldn't answer a bare Symbol — RBS
symbol-literal types let the base declare (:while | :until) and each subclass
narrow to its own literal, something the Sorbet side has no way to spell
(its sigs stay Symbol). Steep caught the widening; the union is the fix,
not a cast.

### Flay stops counting type ceremony: 906 -> 156, and the noise hid a real drift risk (rush-h2u)
The 14n move gets its flay twin: Sorbet sig blocks are declarations, not code —
identical generic sigs are forced (a sig must be a literal block per method) —
so their 712 of 906 mass only padded a budget real duplication could hide
under. flay's own :filters hook takes a Sexp matcher; (iter (call nil sig) ___)
drops every sig from the hashed tree, no subclassing needed. The proof the
noise mattered: under it sat a cluster the top-10 never showed — the option
-cluster predicate (-abc/+abc, not --, sign+letters split) spelled twice, in
Set#option? and InvocationFlags#cluster?, one POSIX concept (XCU set shares
its letters with sh invocation) drifting on two definitions. It is now
Rush::OptionCluster (parse -> nil | cluster; each_letter yields letter+sign).
Reek steered the shape twice: FeatureEnvy moved iteration onto the cluster
itself, then flagged the argv-munching loop — reek 6.5 does check initialize —
which pushed @argv into InvocationFlags as owned state and dissolved the
`rest` parameter threading entirely. Judged idiomatic and left in the 156:
SimpleCommand's select-by-type triple (66, the T.let+each dance is the only
shape both checkers narrow without casts), Registry/FunctionTable (58, two
flat domain vocabularies; a generic base costs more than it saves), and
PatternRemoval's strip_prefix/strip_suffix (32, the POSIX ${x#}/${x%} pair
reads better symmetric). FLAY_THRESHOLD 906 -> 156.

### The last silenced Steep diagnostic comes back on (rush-211.5.11)
UnannotatedEmptyCollection was the one remaining Steepfile silence from the
prototype bootstrap; enabling it costs exactly 7 annotations in 6 files. The
finding worth keeping: an RBS ivar declaration hints a *bare* empty literal
fine (`@jobs = {}` with `@jobs: Hash[Integer, Job]` in sig/ passes), but the
`T.let` generic — shimmed as `[X] (X value, untyped) -> X` — severs that hint
flow for empty hashes specifically, while empty arrays inside `T.let` sail
through unflagged. Asymmetric, likely a Steep 2.0.0 quirk; if a later Steep
starts flagging the `T.let([], ...)` sites too, the same idiom applies. The
fix keeps both checkers at full precision rather than dropping `T.let` (which
would leave Sorbet with an untyped hash): the four ivar sites take the
number.rb dual-annotation idiom — `#:` on the literal for Steep, `T.let`
around it for Sorbet — spread multiline so the assertion lands on the literal
itself (a trailing `#:` after the whole `T.let(...)` call does *not* reach
inside; measured). The three bare locals take a plain trailing `#:`. Steepfile
now configures no diagnostics at all: one ignore (racc parser) is the whole
remaining ledger.

### The untyped-call sweep finds two systemic leaks, not thirteen local ones (rush-211.5.12, dissolving rush-211.5.5)
The drift sweep was scoped as 13 stray untyped calls in 11 files; the dump
(session tooling over Steep's TypeCheckService — StatsCalculator counts,
so the same walk prints file:line + receiver type) measured 38 and then
found most shared two roots. First: the `T.must` shim returned untyped —
`[X] (X? arg) -> X` makes it a proper narrowing generic, and whole chains
retyped at once (five calls, zero source edits). Second, the big one:
sig/strscan_ext.rbs redefined StringScanner methods that rbs 4.0.3's stdlib
now ships (charpos et al.) — RBS::DuplicatedMethodDefinitionError, which
`steep check` never surfaces: it silently drops the ENTIRE class to untyped.
Every StringScanner call in the lexer — even through declared
`@scanner: StringScanner` ivars — stopped being type-checked, and a probe
(`@scanner.definitely_missing?` passing green) confirmed the blindness. The
shim now appends only the genuinely missing String-pattern overloads via the
`| ...` syntax, and the un-poisoned class immediately caught a real gap:
printf's Template destructured `captures` without narrowing. That one fix
cleared all of rush-211.5.5's scanner-boundary scope (tokenizer,
printf_formatter, scanner_predicates) — the bead closes by dissolution, like
mv8.1 before it. The residue was honest per-site work: `T.unsafe(self).send`
dispatch became Method-object dispatch (`method(sym).call` — same table-driven
design, typed receivers, no T.unsafe) in jobs and command_text; the getopts
KEEP sentinel became `:keep` so RBS can spell `String | :keep | nil` (an
Object.new sentinel types as the useless `Object`); Redirect#target got its
real union `Word | HereDoc` (both expand and both carry source_line — only
command_text's post-guard word() needs a cast); tty handles are `IO`, the
job-report/signal-report streams are `_IoStream`. Lesson pinned twice over:
== against a literal-typed CONSTANT does not narrow in Steep (is_a?(Symbol)
does), and untyped dumps beat per-file guessing — measure receivers, not
files. steep stats: 99.88% typed calls; the remaining 11 are test_expr's
dispatch (rush-211.5.6) and parser_support (rush-211.5.7).

### test/[ sheds its last public_send — and the sigil comes up with it (rush-211.5.6)
The operator tables mapped to method Symbols and dispatched by
send/public_send: legal Ruby, invisible to both checkers. The tables now map
to lambdas (the parameter_forms/number.rb idiom — `#:` types each lambda for
Steep, T.let types the table for Sorbet), so every binary and file primary
carries its operand types end to end. Raising the Sorbet sigil to typed:
true was the forcing move: Sorbet rejects `send(sym, *args)` splats outright
(error 7019), which retired the PRIMARY arity table in favour of a pattern
match — `in [op, val]` / `in [val]` — that reads as the XCU argument-count
rule directly. Rubocop then vetoed the trivial `->(val) { val.empty? }`
lambda (Style/SymbolProc), which was the right nudge: a two-entry table
dissolved into two guard lines inside #unary, where -n/-z sit beside the
FILE_UNARY handoff, and three one-line wrapper methods (none?, nonempty?,
empty?) plus two constants left the file. No send/public_send remains in
TestExpr; the 9 structurally-identical FILE_UNARY lambdas sit below flay's
per-node mass threshold, same as number.rb's. Verified against dash beyond
the corpus: 24 probe lines byte-identical, including the POSIX
binary-outranks-negation shapes (test ! = x, test \( = \)) and strtol
strictness. Untyped calls: 11 -> 10, all now in parser_support.

### ParserSupport is typed glue with one named boundary, not a boundary file (rush-211.5.7)
The classification decision the epic tail hinged on: does the hand-written
module racc mixes its `---- inner` into count toward typed coverage, or is it
generated-adjacent and excused? The dump answered: of its 10 untyped calls,
7 were on values whose shape the grammar guarantees deterministically — the
list-accumulation pairs (an and_or plus the separator the grammar rewrites
once it sees what follows) and the simple-command part arrays. Those are now
`type list_entry = [AST::Node, String]` and
`type command_part = Assignment | Word | Redirect`, and the factories type
end to end — Steep even accepts the in-place `entries.last[1] = sep` tuple
rewrite. What remains untyped is exactly 3 calls on one value: on_error's
lookahead, which racc hands back as whatever the semantic stack held — or
literal `false` at end of input. That is the module's one deliberate
boundary, named as such in the .rbs above the racc-surface block
(parse/do_parse/next_token/on_error). The Sorbet sigil stays typed: false
for the same structural reason: do_parse/token_to_str exist only inside the
generated (and Sorbet-ignored) parser.rb, so Sorbet cannot see the host.
Verdict recorded: typed glue, one 3-call racc boundary, and the epic's
coverage story closes at 99.97% typed calls (9007/9010) with every remaining
untyped call named and justified. The wider lexer→parser token seam (the
[untyped, untyped] tuple next_token forwards) stays parked as its own
backlog bead — a Token value object would tame on_error's value too, but it
is a lexer redesign, not a typing chore.

### The token seam gets its vocabulary, and the ledger hits zero (rush-kpj)
The lexer→parser seam carried [untyped, untyped] tuples end to end; it now
speaks three RBS aliases — token_kind (a Symbol tag or the literal
single-char operators the grammar spells as-is), token_value (Word |
Assignment | HereDoc | String | Integer), token ([kind, value], with racc's
[false, false] end marker spelled separately where it can occur) — threaded
through Lexer, TokenClassifier, TokenPredicates and ParserSupport#next_token.
No Token value object: racc requires the 2-array shape at the boundary, so a
wrapper would only add convert/unwrap ceremony — aliases type the tuples as
they are. The typing promptly paid twice. First, on_error's lookahead — the
3-call racc boundary slice 14v documented as permanent — types as
token_value | false, and the respond_to?(:literal_text) duck check became an
is_a?(AST::Word) narrowing both checkers see through: project untyped calls
9008/9008 — zero, the epic's aspirational 100% reached literally. Second,
Steep rejected delimiter(token.last): the here-doc delimiter was being
CLASSIFIED, and a delimiter shaped like an assignment (<<X=1 in command
position) would hand delimiter() an AST::Assignment, which has no #segments
— a latent NoMethodError. Probing shows the shape is grammar-unreachable
(expects_command survives DLESS only via @expect_filename, i.e. after a
redirect op, where racc rejects DLESS before the delimiter is ever lexed) —
but the fix is structure, not a cast: an awaited delimiter is now taken raw,
before classification or aliasing, which is also what dash's readtoken does.
Probes: 7 heredoc shapes (<<-, quoted, reserved-word and X=1 delimiters,
heredoc-first, double heredoc) byte-identical with dash; full rake green.

### The umask alive cluster: 28 triaged, 18 killed, 10 named equivalents (rush-9sr)
The full mutant run's tail showed split_who and target_mask; the whole
UmaskMode ledger was 28 alive (95.42% subject-scoped). Triage sorted them
into three piles. **Dead code**: split_who's `.uniq` — every consumer of who
(target_mask, permission_value, copy_value) ORs per-class bit fields, so
duplicates are absorbed; the dedup came out rather than being spec'd around,
and a comment records why repeats are safe. Removing it also turned the
reduce `|`→`^` mutants from equivalent to killable: an even-count duplicate
(`ua` — a expands to ugo, so u appears twice) cancels under xor, and four
new dash-verified lines (`ua+w`, `ua=w`, `ua=g`, `u+rr`) pin every
accumulator as a true or. **Spec gaps (18 killed)**: `+w`/`=r` — an omitted
who defaults to all classes, previously untested, which alone accounted for
seven split_who survivors; `u=r` at 0o066 pins `=` clearing exactly the
named class (killing the reduce-seed and 7<<→1<< target mutants); `g=o` at
0o427 pins copy_value's 3-bit source window — an unmasked source drags its
neighbour classes into the target (`a=u` pins the multi-who accumulator);
`22` pins octal parsing off the 1777-only fixture (parse_octal→ALL survived
because 1777 clamps TO ALL); `u~w` pins the invalid-OPERATOR path, where the
guard family would leak KeyError through the ArgumentError rescue; and the
trailing comma became an adjudication: dash accepts exactly one (`u+w,`
applies, `,u+w` and `u+w,,` error — a parser artifact), bash rejects, POSIX's
symbolic-mode grammar admits none — standard wins, rush stays strict, the
divergence is pinned in the unit spec and stays out of the corpus. Three
corpus lines (`+w`, `u=r`, `uua+w`) pin the dash-agreeing shapes end-to-end.
**Equivalents (10, documented here)**: split_who's T.must removal (runtime
assert, the 211.8 ceremony bucket); assign_allowed `|`→`^` (bits are always
inside target, so the or never overlaps the cleared region); initialize and
format_symbolic dropping `& ALL` (two's-complement: every reader windows
with >> and &7, which never see the sign bits); format_symbolic `&167` and
letters filter_map→map (letters tests only r/w/x bits; join stringifies nil
to ""); apply_clause `unless OPERATORS.key?(operator)` (key?(nil) is false);
parse_symbolic's split block-form (yields the same fields), limit -2 (any
negative keeps trailing empties) and limit 167 (killable only by a
167-clause mode string). UmaskMode lands at 98.36% with every survivor
named; the full-project score rises accordingly.

### The braced scan learns POSIX brace matching, and quoting context reaches the operator word (rush-no1.1)
ParamScanner took the body of ${...} with `[^}]*`, so any nested expansion
was a syntax error — the project-review probe `${a:-${b}}` exited 2 where
dash prints inner. The fix is two seams. **Scan side**: BracedReader matches
the closing brace per POSIX 2.6.2 — a nested `${` recurses (which scopes
quote handling per level for free), a backslash escapes the next character,
and quoted strings / `$(...)` / `$((...))` / backticks are skipped whole via
the existing SubstitutionReader. The dash-pinned subtleties: a bare `{`
opens nothing (`${a:-{}` prints `{`), and *context* decides what a single
quote is — inside double quotes and here-doc bodies `'` is an ordinary
character (`"${a:-'}'}"` closes at the first `}` and prints `''}`), outside
them it quotes a region. So `quoted:` threads from the call sites:
DollarScanner passes its own flag, HeredocBody is a quoted context (dash
re-scans heredoc ${} words as if double-quoted — `${a:-'x'}` in a heredoc
keeps the quotes), ParamText stays bare. **Expansion side**: the operator
word's re-scan must honour the same context, so ParamSegment hands its
quoted flag to ParameterExpander, which re-scans quoted words with the new
QuotedWord lexer — single quotes ordinary, embedded double quotes removed,
backslash escapes the double-quote set plus `}` (`"${a:-\x}"` keeps the
backslash, `"${a:-\}}"` drops it), and `tilde: :none` (`"${a:-~}"` is a
literal ~) — instead of WordScanner.entire. reek shaped the result twice:
BooleanParameter made `quoted:` a required kwarg at both constructors (call
sites must declare their context), and ControlParameter on the char-switch
turned dispatch back onto the scanner itself (each handler consumes its own
opening character). Two adjacent pre-existing bugs surfaced and are filed,
not fixed here: SubstitutionReader's paren count is not quote-aware —
`$(echo ")")` breaks (rush-no1.9) — and quoting inside an unquoted
`${a:-"x y"}` word is flat by the time the outer pipeline splits and globs
(rush-no1.10). Verified: a 30-probe dash matrix matches on
[stdout, exitstatus], 24 new corpus lines, full rake green.

### test/[ grows its file-type primaries and the dash -a/-o grammar (rush-no1.3, rush-no1.7)
Two beads, one seam. `test`/`[` gains the missing unary primaries — `-t`
(isatty of a numeric fd, not a path), `-p -b -c -S` (file types), `-g -u`
(mode bits) — and the XSI-obsolescent `-a`/`-o` connectives, adjudicated
dash-compatible since POSIX leaves >4-argument test unspecified and the
idiom saturates real scripts. Reading dash's test.c settled the model:
testcmd is a tiny argc switch (binary-primary shortcut at three arguments —
BINOP only, never -a/-o; `!` peel and `( )` strip at three/four) over a
recursive-descent parser (oexpr/aexpr/nexpr/primary) whose t_lex classifies
words *positionally*: a unary primary is an operand when last (`[ -n ]` is
the non-empty test) or before a binary primary (`[ -t = -t ]` compares
strings), and `(` at list end is a word. rush now mirrors that shape —
TestExpr keeps the POSIX table, TestGrammar transcribes the descent with
dash's exact cursor discipline (a leftover word is the "unexpected operator"
error; a missing -a/-o arm is the missing expression, false, so `[ x -o ]`
is true and both arms always evaluate: `[ x -o y -eq 3 ]` still exits 2),
TestTokens is t_lex, TestOperators the shared lambda tables. One divergence,
POSIX's side: dash *zeroes* rather than toggles its negation parity when it
peels `!` twice, so `[ ! ! ! x ]` is true and `[ ! ! -n x ]` false there;
POSIX specifies the four-argument `!` row, rush negates honestly — pinned in
unit specs, kept out of the corpus. `-t` parses its operand with atomax
semantics (padded/signed decimal; junk is "Illegal number", exit 2) and any
unusable descriptor — closed, negative, bignum — is simply not a terminal,
via the port's new tty_fd? (IO.new with autoclose: false). Lint shaped the
result: reek's ControlParameter tolerates case/in on a parameter (and
comparisons when the param also flows as data) but flags pure comparison
chains, NilCheck pushed nil handling into fetch-with-block returns, and the
flog ratchet split TestExpr#evaluate into shortcut/peel. Verified: 147-probe
dash matrix green, 41 new corpus lines, full rake green.

### read learns dash's backslash algebra: continuation, gaps, and the remainder cut (rush-no1.4)
The read builtin cooked its line with gets + gsub(/\\(.)/) + delete_suffix —
no line continuation (printf 'a\\\nb\n' | read x gave a, dash gives ab), and
escapes were stripped *before* splitting, so `a\ b c` split on the protected
space. The fix places escape processing at dash's seam: ReadInput yields one
logical line as annotated [char, escaped] pairs (an odd trailing backslash
run joins the next physical line), and the new ReadFieldScanner splits those
pairs escape-aware. The instructive part was the remainder semantics: dash
probes produced apparent contradictions — `a b \ ` gives y=`b` (escaped
space *dropped*) while `a b c\ ` gives y=`b c ` (kept) — that no local rule
explained. Reading dash's readcmd resolved it: escaped chars live in *gaps
between recorded regions* that ifsbreakup never scans, and ifsbreakup(maxargs)
does count-limited splitting with a cut pointer r — the delimiter that spends
the last variable sets r, later unescaped non-whitespace clears it, trailing
whitespace re-sets it, gap chars touch nothing, and `*r='\0'` truncates. That
one mechanism explains every quirk, including `a:b:` → y=`b` (an exhausting
*non-whitespace* delimiter is cut when nothing follows, though `a:b:c:` keeps
`b:c:`) and ws-run+one-colon trailing removal. ReadFieldScanner transcribes
the state machine (@spaced=ifsspc, Fields@cut=r); a zero-width joint
['', true] carries the region-boundary reset across continuations — without
it `a \<newline>: b` with IFS=': ' absorbs the colon into the preceding
whitespace delimiter, and dash does not. Exit status now follows dash's EOF
rule: success iff the line ended in a newline, so partial final lines and
continuations into EOF assign what they have and return 1. Lint shaped the
design as usual: ControlParameter pushed the escaped-flag dispatch into the
run block, the MemoizedInstanceVariableName/OrAssignment tug-of-war merged
mark/mark_once into one idempotent Fields#cut (sound because r is nil until
exhaustion), and chomp("\n") became delete_suffix — which is also more
faithful, since plain chomp would eat a lone \r that dash keeps. Confirmed
pre-existing and out of scope: prefix assignments (`IFS=: read x y`) are
invisible to the builtin — all 10 diffs in the 87-probe matrix are that seam
(worth a bead). Verified: 77/87 probes match dash, 22 new corpus lines, full
rake green.

### command -p searches the standard's PATH, not dash's, and the child keeps its name (rush-no1.5)
`command -p true` exited 127 because the builtin only understood a literal
leading `-v`/`-V`; `-p`, clusters (`-pv`), `--` and illegal letters all fell
through to "run an external named -pv". The rewrite splits parsing into
CommandOptions — leading `-p/-v/-V` clusters, `--` terminator, first bad
letter recorded as `illegal` (rc 2, "Illegal option -z", non-aborting: probed
that dash continues after it) — and threads `-p` as a search-path override,
never a mutation: CommandLookup takes an optional `path:` that replaces
$PATH in its file resolver only, so `-p -v f` still reports a function and
`-p echo` still runs the builtin (probed: -p moves *only* the file search).
Execution resolves through the new public CommandLookup#executable_path
against SystemCalls#default_path = Etc.confstr(Etc::CS_PATH). Two probed
subtleties shaped the port: dash leaves the child's PATH env untouched
(`command -p sh -c 'echo $PATH'` shows the original), so no env merging; and
the child's argv[0] stays the name as typed (`command -p dash -c 'echo $0'`
prints `dash`), so spawn became spawn(file, env, argv, options) — plain
External#call passes the bare name (kernel $PATH search as before),
External#call_file passes the pre-resolved file. The reek gauntlet rejected
every coalescing shortcut (`exec_path || argv.first` is a ControlParameter;
a separate spawn_file was the third (env, argv, options) DataClump) and the
explicit-file signature it forced is genuinely better. Divergences: dash
resolves -p against a compiled-in defpath (/usr/sbin/ls here) where POSIX
says the confstr value (/bin/ls) — standard wins, pinned in a unit spec and
kept out of the corpus; and bare `command -v`/`-V` exited 127 in rush but 0
in dash (never probed when -v landed) — realigned to the oracle. A 47-probe
matrix matches dash on [stdout, exitstatus] except those pinned path
strings; 18 new corpus lines; full rake green.

### Command substitution learns real $( ) scanning: quotes, comments, and the case hack (rush-no1.9)
SubstitutionReader#parens counted raw parens, so `$(echo ")")` died with
unterminated double quote where dash prints `)` — and since
BracedReader#substitution and HeredocBody reuse #parens, `${a:-$(echo "})")}`
and heredoc bodies broke the same way. The fix is a real scanner: ParenReader
walks the body per POSIX 2.6.3 ("any valid shell script can be used"), in
three pieces the gates shaped. **QuoteSkips** is BracedReader's
single/double/escape family extracted into a shared mixin — flay sat exactly
at its 156 ratchet, so sharing was the only move — and probing dash showed
double quotes must recurse: `$` and backticks stay live inside `"..."`, so
`"$(echo ")")"` skips the inner substitution whole, which transparently fixed
the same blind spot in BracedReader itself. **Comments**: dash starts a `#`
comment at any token start — including right after a redirect operator
(`$(echo x>#)` hangs the paren and exits 2) — but never mid-word (`$(echo a#)`
closes); a word-start flag the operators reset carries this. **The case
hack**: dash accepts the unbalanced pattern paren in `$(case x in x) echo y;;
esac)` and the standard's "any valid script" makes it mandatory, so
CaseTracker keeps a stack of CaseFrames advancing :case_word → :await_in →
:pattern ⇄ :body: a `)` at the construct's base depth in :pattern is swallowed
rather than counted, a grouped `(x)` hands :pattern to :body on its balanced
close, `;;` reopens :pattern, `esac` pops — with keyword-ness gated on a
command-position flag that separators set, CONTINUERS (if/then/do/...) keep,
and ordinary words clear, so `echo case`, `x=case` and `echo esac` stay words.
reek shaped the tracker twice: ControlParameter fires on `frame&.at?(depth)`
in a condition though a plain `at?(depth)` passes, and DataClump flagged the
(text, depth) threading — both dissolved by making the tracker own the depth
and dispatching keywords through registry fetches. Verified: 83 dash probes
(75 matching; the 8 DIFFs are pre-existing residues), 37 corpus lines, full
rake green. Named residues: heredoc bodies inside $() still close at a bare
`)` (pinned in a unit spec); the arithmetic reader stays quote-blind by design
(POSIX arithmetic has no strings — dash errors identically, pinned);
`` \` `` backtick nesting, the arith evaluator accepting `$(('1'))`, unquoted
expansion eating backslashes, and `$(esac)` exiting 0 (cmd-sub bodies re-parse
at expansion) all predate this slice and are noted for follow-up beads.

### PS4 reaches the tracer, and exec 2>&1 smuggles stderr into the corpus (rush-no1.8)
CommandRunner#trace hardcoded '+ '; POSIX 2.5.3 says each xtrace line is
prefixed with the *expanded* PS4. The vehicle already existed: Prompt gained a
third method — trace = render('PS4', '+ ') — so PS4 gets exactly the PS1/PS2
treatment: re-read per trace line, ParamText (parameter expansion ONLY),
render-time default, raw-string fallback on malformed values. Startup
inheritance is free since Environment seeds from ENV. Probing dash found three
divergences, adjudicated standard-over-dash and pinned in unit specs — and the
adversarial verifier then corrected the first two readings, a lesson in
itself: probe the *side effects*, not just the prefix (PS4='`touch /tmp/f` '
proves dash never runs the command). First: dash does NOT execute
substitutions in PS4 — it strips backticks unexecuted, errors $(cmd) back to
the raw string, and genuinely expands only $((arith)); rush keeps all three
literal per POSIX 2.5.3's parameter-expansion-only wording, which doubles as
the recursion-safety guarantee. Second: a failing ${x?} in PS4 does not kill
dash either — it prints a per-line diagnostic and falls back to the raw
string (rc 0); rush's raw-string fallback is the same policy minus the
diagnostic (stderr, outside the model). A backslash divergence is real and
pinned: dash honors \$ as an escape during prompt expansion, ParamText keeps
the backslash literal and expands anyway — POSIX is silent, PS1/PS2/ENV share
the treatment.
Third: dash initializes PS1/PS2/PS4 as *set* variables at startup ('${PS4-U}'
prints '+ '), so explicit `unset PS4` there yields an empty prefix; rush stays
with render-time defaults (unset → '+ '), consistent with its existing PS1/PS2
shape. The standard's "first character repeated per level of indirection"
needs a nesting-depth concept rush's single trace site doesn't have — and dash
never repeats — so a single prefix is documented as correct, not simulated.
The pleasant discovery: stderr is outside the differential model, but
`exec 2>&1` folds trace lines into stdout, so six corpus lines pin PS4
end-to-end anyway — including 'PS4="[$?] "; ...; false; set -x; echo hi',
which proves expansion happens per trace line, not at assignment. Known
neighbouring gap left alone: dash traces bare assignments ('+ A=1'); rush's
tracer only fires on commands with words — trace *content* is a separate bead
from prefix fidelity. Verified: ~22-probe dash matrix, byte-identical stderr
on the agreeing cases, full rake green.

### POSIX bracket subforms compile once across case, removal and globbing (rush-no1.2)
Ruby's two pattern ports both stop short of POSIX brackets: File.fnmatch treats
`[[:alpha:]]` as nested literal punctuation, and Dir.glob returns no candidate.
The fix keeps one language rather than three call-site translations. ShellPattern
owns ordinary wildcard compilation (`*`, `?`, escapes and brackets); BracketScanner
finds the OUTER close while skipping the inner `]` of `[:class:]`, `[=equiv=]` and
`[.collating.]`; BracketExpression lowers the twelve mandatory named classes into
Ruby regexp class syntax and the portable one-character equivalence/collating forms
into literal members. Case and `${x#pat}`/`${x%pat}` meet it through the renamed
predicate `SystemCalls#fnmatch?`, so the existing consumers needed no policy code.

Pathname expansion reuses exactly the same matcher without reimplementing filesystem
traversal: ShellPattern broadens each extended bracket to `?`, Dir.glob discovers the
superset (therefore still owns slash components, symlink traversal, leading-dot rules
and sorting), then `Enumerable#grep` filters with ShellPattern#===. Ordinary patterns
remain byte-for-byte on File.fnmatch/Dir.glob; no-match and `set -f` remain
GlobExpander policy. This staged shape is deliberately limited to one-character
collating elements — Ruby exposes no portable LC_COLLATE tables for primary
equivalence sets or locale-defined multi-character symbols — filed as rush-no1.15
rather than pretending `[[.ch.]]` means the two-character string `ch`.

Oracle adjudication: dash 0.5.13.4 does not match even `[[=a=]]` / `[[.a.]]` in the
installed locales, while POSIX XBD 9.3.5 gives both a one-element meaning in the POSIX
locale; the standard wins, those forms are unit-pinned and intentionally absent from
the differential corpus. Leading `^` is unspecified for shell brackets; this dash
accepts it as negation, so rush follows the practical oracle. The differential surface
pins named/mixed/negated classes in all three consumers (case, removal and real
pathnames); a 544-case scratch matrix adds Unicode alpha under the host UTF-8 locale
and leaves only the two standard-over-dash collation forms. The first review caught
the two structural cases the initial matrix missed: an escaped `]` must not close the
outer bracket, and `[[.].]]` must not mistake its element for the `.]` delimiter.
BracketScanner now skips escapes and searches nested closes only after the opener;
BracketExpression regexp-escapes literal `[`/`]` members without leaking Ruby warnings.

The same review forced the honest quote-provenance seam instead of a matcher hack:
Pipeline#expand_pattern reuses the argv path's segment-level quote shielding (extended
to `] - ! ^`), so case and removal patterns keep quoted metacharacters literal while
ordinary expand_value remains flat. That closes the just-filed rush-no1.14; the broader
operator-default field-split/glob loss remains rush-no1.10. Subject mutation gates finish
above 95%: BracketScanner 96.01%, BracketExpression 97.43%, ShellPattern 96.76%.

### `command` demotes the target by carrying an invocation environment (rush-no1.13)
`command` is a regular builtin, but its second dispatch used to reconstruct the target
from bare shell state: a nested external lost the outer assignment prefix, while a
nested special builtin's BuiltinError escaped to Source and aborted the shell. The
fix makes the simple-command invocation environment explicit at the builtin boundary.
Base accepts an optional fourth environment argument (three-argument direct callers
keep the exported-state default); CommandRunner expands the prefix once, passes the
full child environment into the builtin, and scopes just the prefix names through
Environment#with_temporary. Command forwards that same environment through repeated
`command command ...` layers and into External, including the `-p` resolved-file path.

The temporary scope is name-selective, not a whole-environment rollback: it snapshots
value presence, export and readonly marks for prefix names, restores them in ensure,
and leaves writes to every other variable alive. Thus `HOME=/tmp command cd` changes
to /tmp without changing $HOME, `IFS=: command read` splits on the temporary IFS, and
`X=temp command eval 'X=changed; Y=yes'` restores X but keeps Y. LINENO's dynamic bit is
restored only when LINENO itself was a prefix name — the first version restored it for
an empty prefix too and the existing `unset LINENO` corpus caught the regression. The
independent review caught the opposite ensure edge: applying a prefix to an already
readonly name raises before the body, but restoration still runs; omitting readonly
from the snapshot silently made that name writable. A failed-setup spec now pins it.

Target errors are demoted at the nested dispatch boundary: Command catches the four
fatal session error classes (ParseError, ExpansionError, ReadonlyError, BuiltinError),
reports them and returns 2; control-flow signals (`return`, `exit`, break/continue)
still propagate as the builtin's actual behavior. A 22-probe adversarial matrix and
the corpus pin dot/shift/eval/exit/readonly failures, set -e participation, nested
command, ordinary/default-PATH externals, and assignment-substitution effects.
Two adjacent assignment gaps stay separate: direct special-builtin prefixes are now
visible but still restore instead of persisting (rush-no1.16), and functions plus
readonly external prefixes need the remaining policy work (rush-no1.17). Subject
mutation gates: Environment 97.52%, Command 95.79%, CommandRunner 96.06%.

### Special-builtin prefixes persist, but keep their export attribute (rush-no1.16)
The temporary builtin scope from 15h made prefix assignments visible everywhere but
still restored them after a direct special builtin — `X=old; X=new :` printed old.
CommandRunner now splits at the already-authoritative `special?` decision: regular
builtins enter Environment#with_temporary; a direct special persists only the expanded
prefix slice before invocation. It uses the environment already built for the command,
not CommandAssignments#persist_to, so RHS substitutions execute exactly once. `command
:` still takes the regular path and restores its prefix, which is the property 15h
landed.

Persistence does NOT mean automatic permanent export. A newly introduced `X=1 :`
remains a private shell variable (later printenv misses it), while an already-exported
X keeps its export mark — plain ShellVariables#assign gives both for free. The special
builtin itself can still change the result: `X=prefix export Y=value` persists X
privately and Y exported; `X=prefix unset X` removes X. Prefixes persist even when the
special errors (an EXIT trap sees X), because assignment precedes invocation.
`exec` is the one special that consumes the per-invocation exported overlay directly:
`X=child exec sh ...` must pass X into the replacement even though X's persistent shell
export mark is private, so Exec now uses Base#command_environment.

Verified differentially across colon/export/unset/error traps/exec and command-demoted
control cases; subject mutation gates: CommandRunner 96.79%, Exec 100%.

### Function prefixes and readonly external overlays complete assignment policy (rush-no1.17)
Functions occupy the remaining in-process middle ground: their prefix assignments are
exported and visible during the call, writes to those prefix names are discarded on
return, and every unrelated function side effect remains live. CommandRunner now wraps
only the expanded prefix slice around FunctionRunner, reusing Environment#with_temporary.
The scope encloses FunctionRunner's own local-variable scope and redirect-bound I/O;
return, error, readonly/export/unset changes, and nested external calls therefore unwind
through the same ensure path as regular builtins. A mutation exposed why slicing matters:
wrapping the whole command environment would also restore unrelated variables that were
already exported before the call, silently discarding legitimate function writes.

External overlays were the one path that never called ShellVariables#assign, so a
readonly shell name could be replaced in the child environment. CommandAssignments now
has a side-effect-free validation pass backed by Environment#validate_assignment.
CommandRunner builds the complete environment first, preserving assignment expansion
and command-substitution order, then validates every overlay before constructing or
spawning External. Direct functions and builtins continue to validate while applying
their temporary/persistent slice, retaining sequential special-builtin effects.

Verified by a 14-probe dash matrix covering function export/local/readonly/unset/return,
unrelated exported writes, direct and command-wrapped externals, and expansion before
readonly failure. Independent review found no issues. Subject mutation gates:
Environment 97.49%, CommandAssignments 100%, CommandRunner 96.72%.

### Parameter operator words retain quote provenance through split and glob (rush-no1.10)
`${a:-word}` used to return word through Pipeline#expand_value as a flat String. An
unquoted outer parameter segment then marked the entire result splittable and active
for pathname expansion, so `${a:-"x y"}` became two fields and `${a:-"*"}` globbed.
The expansion stream now carries a fourth FieldPart property — quoted provenance —
alongside text/splittable/break. WordSegment emits ordinary parts polymorphically and
ParamSegment asks ParameterExpander for its structured result; Pipeline shields quoted
glob characters only at the final argv boundary. Scalar consumers still call collapse,
which joins `$@` break boundaries with the first IFS character, so assignments,
redirections, here-docs and arithmetic retain their prior single-string contract.

ParameterParts isolates the operator-word policy. It re-scans with the existing bare or
quoted lexer, expands to parts, and promotes every unquoted region to splittable because
literal text inside word is itself part of the enclosing parameter expansion. Quoted
regions remain anchored and glob-shielded; an outer quoted `${...}` protects every
region. `:-` and selected `:+` return those parts directly. `:=` deliberately assigns
the collapsed raw text and returns one scalar under the OUTER quote policy: dash and
bash --posix both split unquoted `${a:="x y"}` after assigning `a='x y'`. Error messages
and pattern-removal words continue through their scalar/pattern ports.

The independent review found the empty quoted-$@ exception: direct `"$@"` with no
positionals yields zero fields, but selected `${x:-"$@"}` and `${x:+"$@"}` yield one
anchored empty field. Pipeline must keep its direct behaviour, so ParameterParts adds
the anchor only when an otherwise-empty operator word contains a quoted splat; mixed
quoted/unquoted empty `$@` occurrences still produce exactly one anchor.

Verification covered a 72-shape generated matrix (four contexts across quote/IFS/glob/
nested variants), a separate 21-probe operator matrix, zero/nonzero `$@` probes, and 16
new differential corpus cases; all matched dash on [stdout, exitstatus]. Subject
mutation gates: ParameterParts 99.52%, ParameterExpander 95.65%, Pipeline 99.46%,
WordSegment 100%, ParamSegment 97.53%.

### `read` consumes its whole option prefix before naming variables (rush-no1.12)
The original `raw?` test recognized only a first operand equal to `-r`, so a second
`-r` became a variable name and clustered forms were never classified as options.
`read` now peels the leading option prefix once: any number of `-r`/`-rr` flags select
raw input, `--` ends option parsing, and any other letter fails with status 2 before
input is consumed. What follows must be a non-empty list of portable shell names;
therefore `read -- -r` correctly reports a bad variable rather than silently creating
an unreachable environment key. A lone `-` remains an operand and fails the same name
check, matching dash.

The split/input machinery is deliberately untouched. Focused probes and the differential
corpus cover repeated, clustered, terminated and unknown-option forms against dash on
`[stdout, exitstatus]`.

### Noexec is an executor policy, not a parser shortcut (rush-no1.6)
`n`/`noexec` joins the shared option vocabulary, so invocation clusters, `set -n`,
`set -o noexec`, listings and `$-` all use one state bit. The execution guard lives at
both Executor entry points (`run` and `run_async`): ProgramReader still parses every
complete command and therefore still diagnoses syntax errors, but skipped commands do
not expand words, redirect, fork, install traps or change `$?`. Guarding `run_async`
separately matters when `set -n` turns the option on halfway through an AST::List that
was already entered; a later `cmd &` otherwise bypasses the synchronous choke point.

This location also covers startup files, function/compound bodies, eval/dot text and
trap bodies without duplicating policy in their readers. `set -n` itself runs while the
bit is off; every later command, including `set +n`, is only parsed, so the script cannot
turn execution back on. A pre-installed EXIT trap is likewise suppressed, matching dash.
A skipped entry returns the existing status without re-recording it.

POSIX permits `-n` to be ignored by an interactive shell; rush takes that permission and
keeps execution live whenever the interactive option is set. Non-interactive invocation,
runtime, async and syntax-error cases are pinned against dash in the differential corpus.

### fd-facing `test` operands resolve through IoTable without a real-fd rewrite (rush-no1.11)
The concrete redirection blindness did not meet pipeline-fd.md's threshold for reopening
the fd-number migration. Every production IoTable stream that matters here — redirect
File, pipe end, tty — already has a real `fileno`. `FdOperand` rewrites `-t N` to that
fileno and rewrites `/dev/std{in,out,err}`, `/dev/fd/N` and `/proc/self/fd/N` to
`/dev/fd/<stream.fileno>` before the existing test operator calls SystemCalls. The
kernel then answers tty, type, permission, size and mode-bit predicates exactly as it
would after dup2, while the StringIO fake has no fileno and retains its canned unit-test
answers. An explicitly closed logical entry becomes `-1` for `-t` and a nonexistent fd
path for file primaries.

The rewrite sits at TestGrammar's one unary-application seam and receives the builtin's
post-redirection IoTable, so an inner redirect outranks a pipeline binding. `-h`/`-L`
are intentionally excluded: they lstat the literal `/dev/fd` symlink itself, not its
bound target. Signed/blank-padded `-t` numbers retain the existing dash-compatible
number grammar before resolution. Differential coverage includes pipe stdin, an inner
`</dev/null`, closed descriptors, arbitrary fd 5 and persistent exec fd 3; a pty probe
confirms `[ -t 1 ]` changes from true to false under `>/dev/null` exactly like dash.

This is deliberately an operand seam, not universal fd virtualization. Noncanonical
spellings/user symlinks to `/dev/fd`, another process inspecting rush's `/proc/.../fd`,
and opening fd paths as redirection *targets* still observe the interpreter process.
Those require either equivalent resolution at their own seam or the parked real-fd
migration; none is needed to close the standard test/[ primaries named by this bead.

### glibc's regex engine supplies the locale tables Ruby cannot (rush-no1.15)
The one-character BracketExpression compiler remains the portable fallback, but the
production Linux/glibc path now delegates complete bracket semantics to libc. A small
Fiddle bridge translates shell wildcards to an anchored POSIX ERE and calls regcomp /
regexec: unlike glibc fnmatch (probed and found incomplete here), the regex engine
actually consumes Czech `ch` as `[[.ch.]]`, expands `[[=a=]]` to the locale's primary
weight class, and orders ranges by LC_COLLATE. `strcoll` supplies pathname ordering,
with a bytewise tie-break when two names collate equally. Ruby 4 moved Fiddle out of
the default gems, so it is an explicit runtime dependency rather than an accidental
stdlib assumption.

Pathname discovery stays Ruby-owned without under-approximating native matches:
PosixPattern emits a second source that widens *every* bracket to `*` (not the old
one-character `?`), Dir.glob owns traversal/slash/symlink/leading-dot rules, libc
filters the candidates with the exact ERE, and strcoll sorts the survivors. This also
handles a multi-character collating element without binding the ABI-sensitive glob_t
structure. Case, parameter removal and pathname expansion all pass the current shell
locale settings; non-exported runtime assignments are live. Selection is POSIX's
non-empty `LC_ALL` > category (`LC_COLLATE`/`LC_CTYPE`) > `LANG` > `C`, and an invalid
locale falls back to C instead of leaving a stale prior locale active.

The native bridge is deliberately capability-gated by glibc's identifying symbol and
binds only setlocale/regcomp/regexec/regfree/strcoll; unsupported libcs keep the
existing Ruby matcher and its documented POSIX-locale subset. Because setlocale is
process-global, every native operation re-installs its requested categories under one
shared mutex — no per-instance cache can go stale after another adapter changes libc.
regex_t is opaque, so the bridge allocates a conservatively oversized buffer only behind
that glibc gate and always regfree's a successfully compiled pattern. This is the honest portability
contract: locale-complete on tested glibc, safe fallback elsewhere, not a false claim
that Ruby exposes portable collation tables.

The tailored test builds `cs_CZ` with localedef in an isolated subprocess and pins all
four missing dimensions: `[[.ch.]]` consumes `ch`, `[[=a=]]` includes `á`, `[a-c]`
uses locale order, and glob results sort `h, ch, i`. It exercises case, parameter
removal and real pathname expansion, including switching from C to the tailored
locale through an unexported shell assignment. dash 0.5.13.4 fails these tailored
forms; POSIX XBD/XCU is explicit, so this is a recorded standard-over-oracle case.
On glibc the test requires localedef rather than silently skipping; the Docker gate
installs the `locales` package so the defining proof is part of that controlled image.

### The full gate goes parallel: five minutes become one without weakening coverage (rush-yly)
Profiling first changed the scope of the optimization. Two consecutive serial runs took
287.356s cold and 287.660s warm, of which RSpec alone consumed about 280s; parallelizing
only RuboCop/reek/flay/flog/Steep/Sorbet could save a few seconds, not the advertised five
minutes. The safe boundary is therefore one serial Racc compile, then independent child
processes for every gate, with each child's stdout/stderr captured and replayed as one
labelled block. An accidental RuboCop failure during development proved the failure path:
all sibling gates completed, their output stayed uninterleaved, and the final error named
the failed gate. `RUSH_GATE_SERIAL=1` retains the original in-process order for debugging.

RSpec now runs through parallel_tests in at most eight processes. SimpleCov already has
first-class parallel_tests support: each shard gets a distinct command name and writes the
shared resultset under a file lock; the designated final shard waits for every peer, merges
line AND branch coverage, then alone enforces the 95/90 thresholds. The gate deletes
`coverage/` first so an old serial result cannot mask a missing shard. Non-final shards use
SimpleFormatter (no files or console report), preventing partial HTML/JSON reports from
racing the final one. Repeated runs produced exactly the serial totals: 7442/7451 lines
(99.88%) and 1279/1288 branches (99.30%). A single seed is passed to every shard and printed
with a pasteable `RUSH_SPEC_PROCESSES=… RUSH_SPEC_SEED=… rake spec:parallel` reproducer;
parallel_tests additionally prints the exact failed-group command. `--first-is-1` is
load-bearing: it makes even `RUSH_SPEC_PROCESSES=1` the designated `(1/1)` final worker;
a dedicated one-process run confirmed that the merged thresholds still execute.

The first eight-process attempt exposed the real balancing unit: file-size/runtime grouping
still took ~95s because language_spec.rb alone contained 439 generated differential
examples and ran for ~94s. Its case data moved unchanged to support code and eight tiny spec
entry points select cases by stable ID modulo eight. `--group-by found` then distributes those
entry points and the neighbouring heavy differential files deterministically even on a clean
checkout, without committing machine-specific runtime logs. The finished gate measured
57.343s cold and 57.531s warm versus 287.356/287.660s before — essentially **5.0× faster**
(~80% lower wall time). Eight workers were chosen over all 16 host CPUs: 16 saved only another
six seconds while increasing aggregate user CPU from ~247s to ~345s. Full-gate concurrency
raises aggregate CPU (~293s versus ~219s serial) but keeps the per-slice latency win honest;
`RUSH_SPEC_PROCESSES` is the resource-control knob.

### Performance gets a repeatable measuring stick before optimization (rush-lh7.1)
The earlier performance numbers were useful warnings but not experiments: the shell text,
invocation mode, sample count and machine were not pinned. The new opt-in benchmark suite
keeps those variables explicit. It times fresh subprocesses with CLOCK_MONOTONIC, discards
one warmup, retains five raw samples, and reports the median/min/max for three fixed workloads:
a no-op startup, 10,000 while/test/arithmetic increments, and 2,000 rounds of command-free
parameter expansion. Before timing, an unmeasured smoke run checks both empty output and the
workload's terminal assertion (`i=10000` / the final expanded value), so a loop skipped by a
broken shell cannot become a fast result. Every child also has a configurable 30s timeout.
dash runs beside rush as context, never as a timing gate.

Startup needed an honest boundary. Running the harness under `bundle exec rake` normally
injects `bundler/setup` into every child through RUBYOPT and measures Bundler more than rush.
The rush target therefore removes that injection and supplies the installed runtime gems'
load paths explicitly; it approximates an installed executable while still using the exact
bundle under test. The effective executable policy and any lower-level
`SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL` override remain visible in the report, which makes the
next profiling/runtime-policy slice directly comparable rather than requiring another script.

The first committed baseline (Ruby 4.0.5, x86_64 Linux, i9-11900K, default Sorbet runtime
checks, five samples after one warmup) measured median rush/dash milliseconds as follows:
startup **130.553 / 0.526**, while+arithmetic **3950.087 / 6.570**, and expansion-heavy
**2772.894 / 3.965**. The earlier ~2.9s loop observation is not rewritten; the pinned workload
now makes the current ~4.0s number reproducible and future changes attributable.

`rake benchmark` is report-only and remains outside the full gate. JSON schema 1 records the
workload descriptions/counts/hashes, Ruby/OS/CPU/host/revision, an exact digest of all rush
runtime source, Sorbet setting, aggregates and raw samples in `benchmark/baseline.json`. The
source digest makes a baseline from a dirty pre-commit tree attributable even though no commit
hash can name that tree yet. Only an explicit `rake benchmark:check` turns the rush medians into
regression pins, with a deliberately broad 1.5x host-local tolerance; it refuses a different
machine/runtime/Sorbet context, a lower sample/warmup count, or changed workload before comparing.
dash and cross-machine absolute timings are too noisy to pretend otherwise. `benchmark:record`
is the explicit baseline replacement path; sample/warmup/timeout/tolerance knobs support longer
investigations without changing the canonical workloads.

### Runtime sig wrappers belong in diagnostics, not the production hot loop (rush-lh7.2)
StackProf turned the earlier 2x suspicion into a call-stack explanation. On the canonical
10,000-iteration loop with call validation enabled, a 1ms wall profile collected 3,919 samples;
3,772 (96.2% total) passed through `UnboundMethod#bind_call`, with Sorbet's generated medium/fast
validator frames covering 82–89% of the run. The same profile with wrappers disabled collected
1,707 samples and the validator frames disappeared; the top real costs became glob discovery,
field/pattern expansion and scanning. The 2.30x sample-count ratio agrees with the subprocess
benchmark rather than merely correlating with it.

The like-for-like five-sample baseline moved from **130.553 / 3950.087 / 2772.894ms**
(startup / while-arithmetic / expansion-heavy, runtime checks on) to
**124.553 / 1771.277 / 1351.353ms** with checks off: startup improves only 5%, while the two
interpreter workloads improve **2.23x** and **2.05x**. This is a dispatch-wide tax, not one
badly shaped rush method, so a bespoke lean validator would duplicate Sorbet internals while
still charging every call. The policy decision is therefore default-off in the executable.

`exe/rush` now loads a tiny configurator before any rush sig block can evaluate and sets
Sorbet's default checked level to `:never`; `RUSH_RUNTIME_TYPECHECKS=1` selects `:always` for a
diagnostic process. Library consumers and RSpec never call the production configurator, so
runtime validation there remains on, and both static gates still inspect the same `typed: true`
source plus RBS. The configurator itself deliberately has no inline runtime sig: an initial
version wrapped `configure`, causing that very sig to evaluate before its body and making
Sorbet reject the too-late default-level change. It remains statically checked by both systems.

`rake benchmark:profile` makes the StackProf experiment repeatable and writes ignored dumps
under `tmp/`; the same runtime-check switch reproduces checked mode. The committed benchmark
baseline now names the effective policy as well as the lower-level Sorbet environment. YJIT
could not be evaluated on this Ruby build (`ruby --yjit` reports that it was built without YJIT
support), so no speculative YJIT claim is folded into this measured policy.

### Literal argv fields bypass pathname discovery (rush-33e)
The unchecked loop profile exposed a semantic no-op on the hottest argv boundary: every field,
including command names, decimal operands and literal paths, entered locale setup, pathname-pattern
compilation and Dir.glob before falling back to itself. Quote provenance is already encoded at
that boundary as backslash shielding, so GlobExpander can decide cheaply from the final field
without moving pathname policy upstream. Its shield-aware pre-scan skips escaped bytes, treats unescaped
`*`/`?` as active, and treats `[` as active only when a later unescaped `]` can close it. That last
condition matters disproportionately because the canonical loop invokes the `[` builtin 10,001
times; conservatively treating every bare `[` as a pattern retained nearly the whole glob cost.
A malformed bracket with no closer is necessarily literal, while any uncertain closed form still
takes the established ShellPattern/Dir.glob path. Actual patterns therefore retain POSIX bracket,
locale, leading-dot, slash, sorting and no-match semantics unchanged.

The same-host, runtime-checks-off five-sample medians moved from **132.206 / 1869.339 /
1447.719ms** to **126.661 / 1116.898 / 1250.244ms** for startup / while-arithmetic /
expansion-heavy: startup improved 4.2%, while the loop improved **40.3%** and the expansion
workload **13.6%**. The paired 1ms StackProf loop fell from 1,814 to 1,055 samples.
Before, Dir.glob had 196 self samples (10.8%), GlobExpander was on 594 stacks (32.7%), and
PatternScanner appeared on 199 stacks (11.0%); afterward neither Dir.glob nor PatternScanner
appeared anywhere in the profile. Focused spy specs prove that literal, empty, slash-containing,
quoted/escaped and unclosed-bracket fields do not call the glob seam, while wildcard, closed
bracket, escaped-bracket and no-match cases still do. The differential filesystem corpus covers
those boundaries plus dotfiles and nested paths against dash.

### Expansion becomes an append pipeline; the profiler catches three semantic debts (rush-9zz)
The next unchecked profiles made the allocation target concrete rather than stylistic. Before the
change, `Enumerable#flat_map` appeared on **55.4% / 77.5% of CPU stacks**, **58.2% / 74.6% of
wall stacks**, and **84.3% / 88.9% of sampled allocation stacks** for while-arithmetic /
expansion-heavy. The chain was exactly what those stacks suggested: words flat-mapped fields,
fields flat-mapped glob results, segments flat-mapped singleton `WordSegment#field_parts` arrays,
then quote shielding mapped every tuple again; `IfsScanner#result` built `@done + [@current]` and
mapped it back to strings. This was not one algorithm to merge — the POSIX stages remain separate —
but one result array can flow through them. `WordSegment#append_field_parts`, Pipeline's append
helpers and `GlobExpander#append` now write into caller-owned sinks; scalar collapse/pattern
rendering use string accumulators; IfsScanner returns its already-allocated Field objects; default
IFS delimiter sets are shared and custom sets partition once; no-op tilde expansion returns the
original segment array. `flat_map` disappears from every after profile (the residual project-wide
`each_with_object` is 0.4% of the allocation sample, outside this path).

Making the field object cross the split→glob boundary exposed why the old intermediate string was
not merely wasteful. Pipeline encoded quoted glob characters as backslashes, then GlobExpander
removed *every* backslash on fallback, so a real backslash produced by `$x` or `$(...)` was lost
(`x='\q'; set -- $x` became `q`) and `\*` lost its pattern-quoting meaning. Field now retains
literal text and lazily constructs a distinct shielded pattern only when quoted source requires it;
no-match/noglob returns the literal text untouched. One oracle divergence is intentional: with a
pathname `[x]` present, dash expands a dynamic `\[x]` to it while bash --posix preserves the
backslash; rush retains its shield-aware rule from rush-33e, because an escaped `[` does not open a
pattern bracket. A focused no-glob spy pins that standard-aligned side. Two adjacent
ordering/empty-field debts fell out of the required matrix as well: IFS had been read before `${IFS:=:}` in the current word ran, and
unquoted empty `$@` elements were retained under whitespace IFS. IFS is now sampled after each
word's segment expansion, and the forced `$@` boundary follows the first IFS character: a leading
IFS whitespace character drops an unreal empty, while a leading non-whitespace character (or null
IFS) retains it. Ten new differential cases cover both mixed-IFS orders, IFS mutation/default/null,
quoted and unquoted empty `$@`, `$*`'s existing matrix,
backslashes from parameter/command substitution, arithmetic splitting and quoted/unquoted glob
interaction; all 448 language cases match dash.

The measurement surface now reproduces the evidence: `benchmark:profile` emits CPU, wall and
object StackProf dumps for both interpreter workloads, and `benchmark:allocations` reports five raw
`GC.stat(:total_allocated_objects)` samples plus the median after a warmup. A conservative
reverse-order comparison (after tree first, baseline HEAD second), with both suites pinned to CPU 3,
moved startup / while / expansion five-sample medians from **128.892 / 1167.720 / 1298.771ms** to
**132.800 / 1104.721 / 1266.324ms**: the loops improve **5.4% / 2.5%**, while startup's **3.0%**
movement is within the host noise this subprocess benchmark already documents. Exact median
allocations fall from **3,931,347 / 3,063,543** to
**2,671,084 / 2,665,289**, reductions of **32.1% / 13.0%**. The after CPU/wall/object profiles
contain no `flat_map`; the expansion-heavy profile's new dominant cost is glibc collation through
Fiddle for parameter-removal patterns, a different algorithmic boundary rather than hidden
collection churn.

### The public gate reproduces the developer's oracle instead of trusting the runner's (rush-qr5.1)
The CI workflow's design constraint was that no job may weaken what a slice already proves
locally. GitHub's ubuntu-24.04 runner ships dash 0.5.12 while the differential corpus is
pinned against 0.5.13.4, so the native job builds the same checksum-verified dash release
the docker image compiles, caches it by version+sha256, and prepends it to PATH — dev
machine, native CI and the docker oracle now agree on the oracle binary exactly. The
parser-drift audit needed one non-obvious step: `compile` is an mtime-based file task, and
a fresh checkout stamps grammar and generated parser with the same time, so `rake
check_parser_drift` alone would compare the committed parser with itself. CI runs
`clobber_parser` first, forcing a true regeneration before the `git diff --exit-code`.

Rehearsing the docker job with a cold bind-mounted bundle directory — exactly what CI
sees — surfaced a latent bootstrap failure the warm `rush-bundle` named volume had always
masked: Ruby 4 moved fiddle out of the default gems, fiddle 1.1.8 compiles its extension
from source, and the image carried neither libffi headers nor pkg-config, so a fresh
environment could never install the bundle at all. The image now installs libffi-dev and
pkg-config, and the full container gate (2831 examples, syscall/Reline/job-control smokes)
passes from an empty bundle directory. The bind mount doubles as the CI cache: the script's
volume parameter accepts a host path, so actions/cache persists the container's gems
without touching the script's named-volume default.

### Releases become a branch semantics: merge to live releases, the App token makes it observable (rush-qr5.2)
The release pipeline is three deliberately separated concerns. semantic-release on `live`
computes the version from Conventional Commits (the commit convention itself changed with
this slice: `<type>: <summary> (Phase N, Slice Xy)`), bumps `version.rb`, the lockfile's
own-gem line and `CHANGELOG.md` in a `[skip ci]` commit it owns, and creates the tag plus
GitHub Release. That release is created with a GitHub App installation token for one
load-bearing reason: events created with the default `GITHUB_TOKEN` never trigger other
workflows, so a plain-token release would leave `publish.yml` permanently silent — the
failure would be an absence, not an error. Publishing stays in its own workflow on
`release: published` because RubyGems trusted publishing matches the workflow *filename*
plus the `release` environment: OIDC replaces any stored API key, and sigstore
attestations (provenance on the gem page) are only accepted at all when pushing through a
trusted publisher — an API key would not merely skip provenance, the upload of an
attestation is rejected. `rake release` inside the publish job sees HEAD already tagged
and skips its git half, leaving just the attested gem push.

Two facts the dry-run surfaced, worth remembering. First, the repo's early history already
used conventional commits, so `--dry-run --branches main` validated the whole chain
against real history — and computed 1.0.0, because semantic-release's first release is
always 1.0.0 when no previous tag exists; releasing 0.1.0 first requires a manual baseline
tag (`v0.0.1`) on `live`'s initial tip. Second, the gem name `rush` has been taken on
rubygems.org since 2008, so the publish half stays parked until the gem is renamed; the
workflows read the name from the gemspec and only the lockfile-bump sed and this journal
know the string.

### The gem is rush-shell; the shell stays rush (rush-qr5.2)
`rush` on rubygems.org has pointed at Adam Wiggins' abandoned 2008 Ruby-shell since before
this project existed, so the registry identity and the program diverge: the gem is
`rush-shell`, while the executable, the `Rush` namespace, `lib/rush` and the repository
keep their names. The rename touched exactly three self-consistency points — the gemspec
(file and `spec.name`), the regenerated lockfile, and the release bump chain in
`release.config.mjs`, whose sed now covers both lockfile lines that carry the version
(PATH specs at four spaces and CHECKSUMS at two; a first pass missed CHECKSUMS, which a
`BUNDLE_FROZEN=true bundle check` against the bumped tree caught). `gem build` confirms
the artifact identity: rush-shell-0.1.0.gem, executable `rush`.

### The commit convention gets teeth: cog verifies messages at the active hooks path (rush-qr5.2)
`make install-hooks` generates a commit-msg hook that runs `cog verify` (cocogitto 7) with
merge and fixup!/squash! messages exempted — merging `main` into `live` is the release
mechanism and must never be blocked by the linter. The non-obvious part was *where* the
hook lives: beads already owns `core.hooksPath` (`.beads/hooks`, a tracked directory), so
the Makefile resolves the destination through `git rev-parse --git-path hooks` instead of
assuming `.git/hooks`, and the generated file is gitignored by exact path — beads ships no
commit-msg hook of its own, so the slot is free. Verified against real history: all
Slice 18 messages, the release bot's `chore(release): x.y.z [skip ci]` and a merge subject
pass; the pre-18 `Phase N (Slice Xy):` style and unknown types are rejected, including
end-to-end (`git commit` with an old-style message leaves no commit).

### Mutation testing joins CI as the long pole, so it runs beside the gate, not after it (rush-qr5.1)
The mutation gate (`rake mutant:check`) becomes a third CI job. Calibration corrected
itself twice: a small-subject sample suggested ~100 mutations/s, but the full 38,798-
mutation run sustains 36/s on sixteen local jobs — 18 minutes locally, extrapolating to
roughly two hours on a four-core runner. Two consequences: the job is skipped on pull
requests (two-hour feedback is no feedback; pushes to main and manual dispatch still
gate) and it declares no `needs:`, starting beside the gate and the docker oracle rather
than after them. The full run also priced the threshold honestly: 94.43% with 2,161 alive
mutants, so the default 95.0 in the Rakefile was aspiration, not fact. The enforced floor
is now 94.0 — a ratchet (rush-tqq) to be raised as survivors burn down, never lowered. The shared native toolchain (pinned dash build, localedef and
libffi inputs, Ruby from .tool-versions with a cached bundle) moved into a composite
action, `.github/actions/setup`, so the gate and mutant jobs consume identical
environments and the dash pin lives in one place next to the Dockerfile's.

### The release becomes a button, and the same token rule bites twice (rush-qr5.2)
Two operational workflows close the release loop: `cut-release.yml` (workflow_dispatch)
merges `main` into `live`, and `backmerge.yml` (release published + manual) returns the
bot's version-bump commit to `main`. The rule that created the App token in the first
place applies to both ends of the pipeline: the *cut* push must also be made with the App
token, or release.yml would never fire — recursion prevention silences pushes exactly like
it silences releases. The cut's first run doubles as bootstrap: it creates `live` from
`main` and lays the `v0.0.1` baseline tag, because semantic-release's first release
defaults to 1.0.0 when no tag exists; the bootstrap push itself releases nothing, and the
first `feat` merged afterwards computes 0.1.0. All release-path workflows share one
concurrency group (`release`, no cancel), so cut → release → publish/back-merge serialize
instead of racing.

### Docs split by audience: the README serves shell users; types already document the API (rush-qr5.2)
The README flipped from developer-notes to a user-facing page: install, invocation surface,
what of POSIX §2 is implemented, and — the part that differentiates rush — the verification
machinery itself (differential oracle, coverage, mutation gate, dual type systems) as the
answer to "why trust a shell". The deliberate non-decision is API documentation: types are
already stated twice with machine checking (inline `sig {}`, RBS under Steep), so YARD
`@param`/`@return` tags would be a third, uncheckable copy that drifts. When a docs site
lands (rush-366) it will render signatures straight from Sorbet sigs via yard-sorbet,
leaving the constraint-explaining prose comments exactly as they are. The gemspec now links
the changelog and issue tracker so the rubygems.org page points somewhere useful.

### The first CI run audits the audit: a stale lint cache and a pidfile race (rush-qr5.1)
GitHub's runners falsified two things the local gate had been vouching for. First, RuboCop:
raising TargetRubyVersion to 4.0 activates Style/ReverseFind, but the local result cache
kept serving green for unchanged files, so the offense (`reverse.find` → `rfind` in the
background-runner spec) only surfaced where no cache exists — CI. An uncached sweep found
exactly one masked offense; the lesson is that a config-affecting change deserves one
`rubocop --cache false` pass before trusting the local gate. Second, the probe-runner
timeout specs read a descendant's pidfile immediately after ProbeTimeout: on a loaded
runner, interpreter start-up loses the race against the stubbed one-second timeout and
`Integer('')` raises. The stub is now three seconds and the read waits for the write with
a bounded grace window — the assertion is unchanged, only its timing assumptions widened
to match slower machines.

### Release pushes ride the checkout credential; the bot files no issues (rush-qr5.2)
The first live release run failed twice in one AggregateError, and the two errors had
different owners. EGITNOPERMISSION was semantic-release core: a GitHub App installation
token embedded bare in an https push URL does not authenticate — checking out WITH the app
token instead persists a proper x-access-token credential, and semantic-release keeps the
plain remote URL once its dry-run push probe passes. The 403 was the @semantic-release/
github plugin's fail hook trying to create its label ("x-accepted-github-permissions:
issues=write") to open a release-failure issue. Rather than widen the app's permissions,
the comment/label features are disabled in config: failures are visible in Actions, and
the app keeps the minimal contents-write surface (plus pull-requests for backmerge's
conflict PRs).

### One concurrency group is one pending slot: the shared group evicted the release itself (rush-qr5.2)
The button's second press exposed a GitHub Actions semantics detail the shared `release`
concurrency group design missed: a group holds at most one running and ONE pending run,
and a newly queued run evicts the previously pending one even with `cancel-in-progress:
false`. The cut's push to `live` spawned Release and Back-merge simultaneously into the
group the cut itself still occupied; Back-merge took the pending slot and Release — the
actor the whole pipeline exists for — was cancelled two seconds in. Serialization is only
needed between runs of the *same* workflow (their branches differ; there is no shared-ref
race between different ones), so each workflow now owns its group: `cut-release`,
`release`, `backmerge`, `publish`. The 18g journal claim that one shared group makes the
pipeline serialize was exactly the bug.

### The mutation gate needs queue semantics, not cancellation (rush-tqq)
Two green pushes in a row still produced zero completed mutation runs on CI: the release
loop's back-merge pushes to main kept tripping ci.yml's cancel-in-progress and killing the
two-hour sweep mid-flight — a gate that never finishes gates nothing. The mutation job now
lives in its own workflow with `cancel-in-progress: false`: the running sweep always
completes, only the newest push occupies the pending slot, and pull requests never trigger
it. Back-merge merge commits additionally carry `[skip ci]` — their tree is main content
CI just proved plus the bot's version bump, so re-gating (and re-cancelling) added nothing.

### Allocation counts ratchet where timings cannot: zero-spread medians, absolute headroom (rush-1eo.2)
Twenty independent process invocations (5 samples after 1 warmup each) produced
byte-identical medians in all twenty runs for both canonical workloads: while_arithmetic
2681063, expansion_heavy 2667091 — spread exactly zero. The only within-process variance
is a first-measured-sample residue the warmup does not fully absorb (+116 objects on
while, +5 on expansion), which the median already discards; three samples are therefore
as good as five for the gate form. An `env -i` probe pinned the environment-shape effect:
stripping ~50 environment variables moves both medians by exactly −168 objects (~3.4 per
var, from Environment's ENV copy), so a CI-versus-developer-host delta is bounded well
under ±500 objects — which is why AllocationCheck deliberately compares ruby/platform/
typecheck-policy context but not host/os/cpu. Budgets are the recorded median plus ~2k
absolute headroom (2683000 / 2669000): an order of magnitude above the environment bound,
five times below the smallest structural regression (+1 object per while iteration is
+10k). A relative budget was rejected — 1% here is ~27k objects, room enough to hide a
real per-iteration leak. Injected-regression proof: three throwaway objects added to
ArithmeticExpander#expand moved the medians by exactly +30000/+6000 and the check failed
both cases with observed-versus-ceiling messages. The budget workflow is asymmetric by
design: after an improvement, re-record the baseline and lower the budget in the same
reviewed slice; raising a budget demands a justified commit body. `rake
benchmark:allocations:record` writes only the baseline — ceilings are hand-edited or not
at all.

### Timing budgets separate from the baseline — the ratchet finally captures the win (rush-1eo.4)
The committed timing baseline still described pre-optimization rush (while_arithmetic
1771ms median where current reality is ~1096ms), and because the old check derived its
ceiling as baseline x tolerance, re-recording was the only way to tighten it — the exact
"recording legalizes" trap the epic names. The timing check now shares AllocationCheck's
frame (BaselineCheck): the baseline is attributable evidence that pins context, sampling
and workload identity; benchmark/timing_budgets.json holds the only ceilings, hand-edited
and reviewed. Fresh baseline recorded on the quiet pinned host (startup 125.6ms, while
1096.5ms, expansion 1210.8ms — the Phase-8 improvements are now the recorded reality);
budgets sit at median x 1.5 rounded up (190 / 1650 / 1820ms) as the host-local
catastrophic alarm — notably the pre-optimization while median would now breach its
ceiling, which is precisely the ratchet the old scheme could not express. Timings stay
out of the default gate: the full context (host/os/cpu) must match, so the alarm is
meaningful only on the recording host; portable timing evidence remains the same-runner
A/B lane (18q scaffolding, thresholds pending in rush-1eo.5).
