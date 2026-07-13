# Simple command source order

## Decision

Store the original source-order simple-command parts on `AST::SimpleCommand#parts` while keeping the
existing grouped accessors (`#assignments`, `#words`, `#redirects`). The grouped accessors are now
derived from `#parts`, so current execution code keeps its API and future execution work can opt into
the original order without changing the parser again.

`AST::SimpleCommand.new(parts)` is the sole canonical constructor: it receives the final source-order
array and stores it directly. `ParserSupport` calls that constructor with its accumulated prefix,
command word and suffix in grammar order. Tests and compatibility callers that only have grouped
arrays must say `SimpleCommand.from_groups(assignments, words, redirects)` explicitly; that factory
creates the artificial assignments-then-words-then-redirects order and is never a parser path.

No separate `SimpleCommandPart` wrapper is needed yet: the part's concrete AST class (`Assignment`,
`Word`, or `Redirect`) is the tag, and the original objects are preserved.

## Evidence and motivation

POSIX 2.9.1 describes a simple command as a source-order sequence of variable assignments,
redirections, and words; shells save the assignment/redirection words during parsing and then apply
expansion/redirection rules in a defined order. The old rush AST kept source order only transiently
inside `ParserSupport#make_simple_command`; once `AST::SimpleCommand` was built it retained only three
grouped arrays. That was enough for the behaviours already implemented, but it was lossy.

Dash probes show why keeping the order is useful even when execution still uses grouped accessors:

- command-word substitutions are expanded before command redirections:
  `echo $(echo err >&2) 2>f` leaves `f` empty;
- assignment substitutions attached to a command or to a no-command assignment/redirect simple
  command see the command redirections:
  `X=$(echo err >&2) true 2>f` and `X=$(echo err >&2) 2>f` both write `err` to `f`;
- redirections may appear before or after the command word (`>out echo hi`, `echo hi >out`) and are
  semantically equivalent for today's implemented cases, but their original position is still part of
  the grammar's simple-command shape.

The source-order array is therefore a small structural investment: it does not change execution
semantics in this slice, but it prevents future order-sensitive fixes from having to recover ordering
from already-partitioned groups.

## Current consumer contract

Current consumers should keep using the grouped accessors unless they are deliberately implementing an
order-sensitive POSIX 2.9.1 rule:

- `CommandRunner` uses `#words` for argv expansion, `#redirects` for redirection setup, and
  `#assignments` through `CommandAssignments`;
- parser/AST tests assert both grouped access and source order;
- production construction passes source-order parts directly to `SimpleCommand.new`; grouped test
  setup uses the deliberately named `SimpleCommand.from_groups` factory;
- `#parts` is the canonical source-order representation and may contain `Assignment`, `Word`, and
  `Redirect` objects only.

## Follow-up trigger

If execution semantics need to distinguish command-word expansion order, assignment expansion order,
and redirection setup more precisely, build that on top of `SimpleCommand#parts` instead of adding
parallel parser state. In particular, assignment command substitutions observing same-command
redirections should be handled as an execution slice, not by changing the parser shape again
(`rush-n5b.20`).
