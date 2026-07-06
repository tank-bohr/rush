# Word expansion ownership boundary

## Decision

Keep the current split:

- `AST::Word` / `AST::WordSegment` remain the parser payload: ordered, quote-aware syntax
  fragments with small segment-local expansion hooks.
- `Expansion::Pipeline` remains the POSIX word-expansion orchestrator: expansion ordering,
  context-sensitive tilde rules, field splitting, `$@` multi-field breaks, quote escaping, and
  pathname expansion.

Do **not** migrate to a visitor/registry over word-segment kinds in Phase 3.

## Why this is the right boundary now

`WordSegment#expand(executor)` is deliberately narrower than "word expansion". A segment may turn
its own payload into scalar text (`$x`, `$(...)`, `$((...))`, or a literal), but it does not decide
whether that text is split, globbed, tilde-expanded, or joined into a redirection/assignment value.
Those decisions depend on the word's execution context and on neighbouring segment boundaries, so
they belong in `Expansion::Pipeline` and its method objects.

The split matches the project's broader architecture rule: polymorphic payload objects own the
single operation that varies by kind (`Node#execute`, `WordSegment#expand`), while ordered shell
semantics live in orchestration objects. A visitor/registry would centralise dispatch, but it would
buy little today: the segment set is small and stable, parameter-expansion complexity already lives
behind `Expansion::ParameterExpander`/`ParameterForms`, command substitution has its own runner, and
arithmetic has its own parser/evaluator. Moving the dispatch outward would mostly replace simple
polymorphism with a type switch over AST payload classes.

## Guardrails

The current design stays healthy only if the boundary stays narrow:

- segment classes may know their payload and quote/splitting role;
- segment classes may delegate to specialised expanders through the injected `Executor`;
- segment classes must not perform field splitting, pathname expansion, or context-dependent tilde
  expansion;
- segment classes must not call OS APIs directly (`SystemCalls` remains the only impure port);
- `Expansion::Pipeline` must not grow `case`/`is_a?` dispatch over segment subclasses.

## Revisit triggers

Reopen this decision and consider a dedicated expansion visitor/registry if one of these happens:

1. a new segment kind needs cross-segment state before scalar expansion;
2. two or more segment classes grow non-trivial algorithms instead of delegating to method objects;
3. `Expansion::Pipeline` starts branching on concrete `WordSegment` subclasses;
4. the open `WordSegment#value` type becomes the dominant source of Steep/Sorbet escapes;
5. POSIX expansion work requires reordering segment-local expansion relative to splitting/globbing.

Until then, keep the current polymorphic segment expansion and spend new complexity in specialised
`Expansion::*` collaborators rather than moving dispatch out of the AST payload.
