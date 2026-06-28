# rush — engineering journal

Durable lessons and cross-cutting findings from building rush, a pure-Ruby POSIX `sh`
whose oracle is **dash**. This is the lab notebook, not the backlog:

- **What's next / open bugs** → beads (`bd ready`). Not here.
- **Per-slice blow-by-blow** → `git log` (commit bodies are detailed).
- **Design decisions** → `docs/architecture/`.
- **This file** → the *why* and the non-obvious gotchas worth not re-learning.

Verification model for every behavioural claim below: bit-exact vs `dash -c`, comparing
**`[stdout, exitstatus]`** (stderr ignored), via the differential corpus
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

**Open (filed in beads, found by the 7aj fuzz):**
- **function-call redirects not applied to the body** (`f >file`): `CommandRunner#run_function`
  doesn't thread the redirected io into the function body.
- **`shift` past `$#` doesn't abort** (dash: special-builtin error → 2; rush no-ops, status 1).
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

### `exec` redirect-only permanence — the remaining path-2 piece (beads `rush-6wx.1`)
`exec >file` / `exec 3>file` must persist for the rest of the shell. Already wired via
`executor.replace_io(@io)`; the dup form (`exec 2>&1`) already works because no new stream is
opened. The bug: `with_redirects`' `ensure` closes the file opened over base, undoing it. Fix:
skip the close when the executor committed the io (`io.equal?(@io)` after `replace_io`).

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
