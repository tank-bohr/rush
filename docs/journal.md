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
(`spec/integration/differential_spec.rb`) plus ad-hoc randomized fuzzing.

---

## Charter — what rush is actually investigating

rush is a **research project about Ruby (the language + ecosystem), not about shells**: a
POSIX `sh` is a deliberately *solved* problem (dash is the oracle, correctness is externally
decidable), so all effort goes to the *how* — under extreme quality pressure (RuboCop +
Sandi-Metz + reek + meaningful coverage pressure + mutant + two type systems), what does the
ecosystem offer for non-trivial code, and what code results? Coverage aims at 100% where it is
meaningful, but shell semantics cross process boundaries that SimpleCov cannot observe; the
metric serves the design, not the reverse. Two type systems (RBS/Steep and inline Sorbet) are run
independently on the same code — the task is to compare how each fares.

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
