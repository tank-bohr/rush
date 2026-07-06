# Architecture conventions

The living design rules every slice follows. They exist so the Sandi Metz limits
(class ≤100 lines, method ≤5 lines, ≤4 params — see `.rubocop.yml`) fall out naturally
rather than being fought. Structure is also described in `pipeline-fd.md` and the code itself;
this file is the *why* behind the shape.

## The pipeline

Unidirectional: **Source → Lexer → Racc Parser → AST → Expander → Executor**, over shared
**shell state**, with one feedback wire (the parser nudges lexer state for POSIX Grammar
Rules 1–9) and **all OS access funnelled through one injectable port** (`Rush::SystemCalls`).

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
