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
Sandi-Metz + reek + 100% coverage + mutant + two type systems), what does the ecosystem offer
for non-trivial code, and what code results? Two type systems (RBS/Steep and inline Sorbet) are
run independently on the same code — the task is to compare how each fares.

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
- **`n>&-` closes** fd n → a `ClosedStream` whose I/O raises `Errno::EBADF` (a write fails the
  command with status 1, caught in `CommandRunner#builtin`; the shell continues) and which
  `IoTable#to_spawn_options` maps to `:close`. Dup *from* a closed/unopened fd → `RedirectError`
  (status 2, shell continues); a **non-numeric** dup target → `BuiltinError` (fatal).
- **Flush/close after the command** (`close_opened_over`): a redirect's target is closed when the
  command finishes, identified by object-identity diff `io.ios - base.ios`, so inherited streams
  and pipe ends are untouched. Redirect files are opened in **sync mode** so a forked subshell's
  output survives its `exit!` (which flushes only the std streams).
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

## Dev tooling (beyond rubocop + rspec + 100% coverage)

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

#### Tightening pattern: value-level invariants under a 100% coverage gate
Recurring across the hand-typing batches (`Status.of`, `Scope#declare_local`/`#end_scope`,
`CommandLookup#verify`, `Environment#exported`): the code is correct because of an invariant the
type system can't see — *absent exitstatus ⟹ present termsig*, *the popped frame is non-nil
because it's paired with begin_scope*, *terse is only called behind a `known?` guard*. Steep flags
these as `NoMethod`-on-`nil` (or on a union member). The **coverage gate shapes the fix**: the
obvious nil-guards (`x || default`, `x&.m`, `return unless x`) all add a branch whose
invariant-false side is unreachable → it can never be covered → the 100% gate fails. So instead
**pin the type with a branchless, behaviour-preserving coercion on the only reachable path**:
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
Sorbet⟂linter frictions, same flavour: an anonymous block splat `{ |*| … }` (ClosedStream's EBADF
stubs) is fine for RuboCop but Sorbet forbids it (srb.help/3012) — naming it `|*_|` satisfies Sorbet
but trips reek's `UncommunicativeVariableName` (the project accepts only `e`), so ClosedStream is
exempted there. **Lesson so far:** adding a second type system to existing code mostly costs you at
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
`raise` in a mixin has no resolvable self — the same fix ClosedStream already used).

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

### mutant — usable, on-demand only
mutant 0.16.3 is **free for OSS** (rush is MIT + public; `--usage opensource`, no signup) and
actively maintained. The parse+unparse roundtrip it relies on handled **all 111 lib files
cleanly** (`unparser` 0.9.0), so the `parser/ruby33`-grammar warning is cosmetic. Kept out of the
default gate: it reruns the ~60s suite per mutation, far too slow for a per-slice gate; it belongs
in a `rake mutant` task / CI. Its payoff is exactly what 100% coverage cannot show — whether the
assertions actually *kill* mutations.
