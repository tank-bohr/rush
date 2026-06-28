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
