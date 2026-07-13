# Architecture conventions

The living design rules every slice follows. They exist so the Sandi Metz limits
(class ≤100 lines, method ≤5 lines, ≤4 params — see `.rubocop.yml`) fall out naturally
rather than being fought. Structure is also described in `pipeline-fd.md`,
`forked-execution-modes.md`, and the code itself; this file is the *why* behind the shape.

## The pipeline

Unidirectional: **Source → Lexer → Racc Parser → AST → Expander → Executor**, over shared
**shell state**, with one feedback wire (the parser nudges lexer state for POSIX Grammar
Rules 1–9) and **all OS access funnelled through one injectable port** (`Rush::SystemCalls`).

## Interpreter state and mutation ownership

`Executor` is the interpreter's execution environment: it wires execution policy, the current base
IO table, registries, expansion, traps, errexit and jobs around one `ShellState`. `ShellState` is the
POSIX state aggregate: it deliberately exposes domain objects such as variables, options,
positionals, functions, aliases and traps for those objects' own APIs to mutate. Neither class is a
metric-driven decomposition target, and callers should not gain facade methods that merely repeat a
collaborator's API.

Cross-object writes have these owners:

- Ordinary option changes go through `ShellState#set_option`; it alone couples `Options#set` to the
  `ShellVariables` allexport mirror. `:monitor` is the deliberate live-executor exception:
  `JobControl` owns its flag together with signal, terminal and process-group side effects, so its
  raw `Options#set(:monitor, ...)` calls must not spread. Invocation may seed the flag through
  `ShellState#set_option` before an executor exists; `JobControl#startup` clears and re-enables it to
  apply or refuse the live side effects.
- `ShellState` owns `$?` and `$!`: status changes use `#record_status` (or the restoring
  `#preserve_status` scope), and the async parent publishes its launch pid through
  `#record_background_pid`. `Executor#run` via `TrapRunner#complete` publishes normal synchronous
  status, while `Executor#run_async` publishes async launch success. Startup, REPL, EXIT-trap,
  command-substitution and loop-control boundaries that need an early status still use only
  `#record_status`. `BackgroundRunner` is the parent-side `$!` writer.
- `Executor` owns the current base `IoTable`. `#with_io` is a scoped overlay restored by `ensure`;
  `#replace_io` is durable and is reserved for redirect-only `exec` and forked async-child stdin
  isolation. Command-substitution status is separate executor state, written only through
  `#reset_cmd_sub_status` / `#record_cmd_sub_status`.
- `JobTable` owns job entries, wait/reap state and durable job-control state. `JobControl` is a
  stateless policy view over it; it does not become a second state store. The other mutable objects
  exposed by `ShellState` likewise own their domain mutations behind their existing APIs.

## Rules

- **One impure class.** `Rush::SystemCalls` is the *only* class that touches the OS — thin
  one-line wrappers over `Process`/`IO`/`Dir`/`File`/`Signal`/`Etc`. It is injected through
  CLI → Executor → runners/builtins/expanders. In specs a fake (`spec/support/fake_system_calls.rb`)
  stands in and can raise `Errno::*` on demand, so every error branch is reachable without
  spawning real processes. **Never call `Process.*`/`File.*`/`IO.pipe`/etc. directly outside the
  port.** Real multi-process behaviour is verified differentially vs dash, not in-process.

- **Registries, not `case`.** Variability lives behind O(1) name→class registries: builtins,
  redirections, parameter-expansion forms, `set` options, traps. Adding a feature = adding a
  small class + a registry entry, never growing a `case`.

- **Polymorphic dispatch.** `executor.run(node) = node.execute(self)`. No `case`-on-AST-type
  anywhere — each AST class owns its `#execute`.

- **Method objects for long algorithms.** Any routine that won't fit in 5 lines becomes a class:
  `initialize` captures inputs, one public `#call` chains ≤5-line private steps. This is how the
  method-length limit is met without cramming.

- **One class per concept.** Keeps classes under the 100-line limit and the require graph legible.

- **Never `eval`.** Arithmetic `$(( ))` is a self-contained Pratt evaluator over Integers
  (64-bit two's-complement), never `Kernel#eval`.

- **Logical PWD.** `cd` maintains a *logical* `PWD`/`OLDPWD` string (POSIX), not `Dir.pwd`,
  which would resolve symlinks.

## Parser & lexer

- `grammar/shell.y` (POSIX §2.10, transcribed) is the **source of truth**. `lib/rush/parser.rb`
  is **generated** by racc, committed, and excluded from rubocop/coverage/metrics. Regenerate
  only via `bundle exec rake compile`. The default `bundle exec rake` intentionally stays fast;
  use `bundle exec rake check_parser_drift` as an explicit audit when touching the grammar or
  generated parser, and in release/CI flows that want the extra check. Treat parser conflicts as
  grammar-design events, not something to hide with precedence rules.
- The lexer is **context-sensitive** (POSIX Grammar Rules 1–9) centralised in `LexState` +
  `TokenClassifier` — the hardest part; get it wrong and `echo if` mis-parses. It is **pure**
  (no OS calls) and **defers all expansion**, emitting a `WordNode` of typed segments
  (`:literal`/`:single`/`:double`/`:param`/`:cmd_sub`/`:arith`/`:tilde`) that preserve quote
  provenance. `word-expansion-boundary.md` pins the ownership line: segments do scalar,
  kind-local expansion; `Expansion::Pipeline` owns context, splitting, and globbing.
- `simple-command-order.md` pins the simple-command AST shape: `AST::SimpleCommand#parts` keeps the
  original assignment/word/redirect order, while grouped accessors remain the execution-facing API.
