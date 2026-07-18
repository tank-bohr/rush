# Sorbet typed-send coverage ledger

This is the measurement and prioritization record for `rush-435`. It measures where Sorbet sees
`T.untyped`; it does **not** claim that counter movement alone improves the implementation. The
normal gate remains `bundle exec rake sorbet`, and RBS/Steep remains an independent model.

## Baseline provenance and reproduction

The baseline was recorded at `2026-07-16T19:38:12Z` from source revision
`051c547cee7b6c24307b9bbe7ed23b2a4f0893a5`. The source tree matched that revision; the only staged
change was the tracker claim for `rush-435.1`, which is outside both checkers' inputs.

- Ruby: `ruby 4.0.5 (2026-05-20 revision 64336ffd0e) +PRISM [x86_64-linux]`
- Sorbet: `0.6.13320`, git `48f0881afa809e9b6239de89ae73c5ce5257a2fb`
- Steep: `2.0.0`

Use the raw `sorbet-static` executable, as the rake gate does. The `srb` wrapper discovers bundled
RBIs that are deliberately outside rush's configured input.

```sh
bundle exec rake compile
bin=$(bundle exec ruby -e \
  's=Gem::Specification.find_by_name("sorbet-static"); print File.join(s.full_gem_path,"libexec","sorbet")')

"$bin" --version
"$bin" --track-untyped=everywhere --counters \
  > /tmp/rush-sorbet-counters.txt 2>&1
"$bin" --track-untyped=everywhere --print=file-table-json \
  > /tmp/rush-sorbet-files.json 2>/tmp/rush-sorbet-files.err

# Location-level classification probe. Exit 100 is expected because every 7018
# diagnostic is deliberately reported; this does not change any source sigil.
status=0
"$bin" --typed=strong --isolate-error-code 7018 \
  > /tmp/rush-sorbet-strong-7018.txt 2>&1 || status=$?
test "$status" -eq 100

# Planning envelope for the remaining no-sigil generated parser. Every explicit
# sigil is already true, and the configured generated-file ignore keeps this green.
"$bin" --typed=true --track-untyped=everywhere --counters \
  > /tmp/rush-sorbet-forced-true-counters.txt 2>&1

bundle exec steep stats --format=csv \
  > /tmp/rush-steep-stats.csv 2>/tmp/rush-steep-stats.err
```

`--print=untyped-blame` is not the location census for this baseline. Sorbet's blame graph requires
a binary built with its optional `untyped-blame` configuration; the prebuilt 0.6.13320 gem emits an
empty report. The forced-strong 7018 probe above is reproducible with the shipped binary and exposes
usage locations, but it is a diagnostic experiment, not the normal typed-send metric.

## Inventory counters (rush-435.1)

These figures preserve the pre-ratchet inventory snapshot. The live budgets and progress table below
advance after each typing slice.

| Metric | Value |
|---|---:|
| Typed sends | 11,085 |
| Total sends | 12,401 |
| Untyped sends (`total - typed`) | 1,316 |
| Typed-send ratio | 89.39% |
| Normal untyped usages | 1,669 in 147 files |
| Forced-strong 7018 diagnostics | 1,827 in 153 files |
| Unique forced-strong file/line pairs | 980 |
| Send-shaped 7018 diagnostics | 936 (879 true, 56 false, 1 generated) |
| Forced-true planning envelope | 11,290 / 12,800 typed sends (88.20%) |
| Signatures in Sorbet's counter scope | 1,682 |

These are three different measures:

- **typed sends** are the epic's coverage metric: `11,085 / 12,401`;
- **untyped usages** include returns, arguments, branches, fields and other flows, not only sends;
- **7018 diagnostics** force every input to `typed: strong`, so normally unchecked bodies also
  report, and one source location may produce several diagnostics.

The normal 1,669 usages come from the typed-true implementation. The forced probe adds 156
diagnostics from the five explicit `typed: false` files and two from the generated parser,
producing 1,827. Neither usage count is an expected typed-send gain. Of those diagnostics, 935 are
ordinary calls on an untyped receiver and one is an untyped splat call: 879 in already typed-true
source, 56 in the five false bodies, and one in the generated parser. This send-shaped subset is a
prioritization surface, not a one-to-one reconciliation with Sorbet's 1,316-send counter gap.

### Scope and sigils

`sorbet/config` names `lib`, `exe`, and `sorbet/rbi`, and ignores diagnostics from the generated
`lib/rush/parser.rb`. The observed file table is more precise than that intent:

| Input class | Files |
|---|---:|
| `lib/**/*.rb`, explicit `typed: true` | 198 |
| `lib/**/*.rb`, explicit `typed: false` | 5 |
| Generated `lib/rush/parser.rb`, no sigil | 1 |
| `sorbet/rbi/**/*.rbi`, explicit `typed: true` | 4 |
| **Total** | **208** |

The aggregate counter calls this 202 true and 6 false; the latter folds the no-sigil parser into the
false bucket. That is the inventory snapshot: the four implementation-typing slices raised their
owned sigils and the later slices added narrow Reline, builtin-Data and shell-Data shims, so the current ratchet
scope is 211 inputs (210 true plus the no-sigil generated parser). The parser remains in input
accounting even though its diagnostics are ignored.
The extensionless `exe/rush` is configured through `--dir ./exe` but is absent from the file table,
so it is outside this baseline. A later scope change must record a side-by-side baseline rather than
silently moving the denominator.

Steep checks 203 implementation files under `lib` (all 204 Ruby files except the generated parser),
not Sorbet's current seven RBI inputs or the executable. Its current receiver-based ledger is 12,110 /
12,138 typed calls (99.77%). That percentage is not comparable to Sorbet's send metric; even their input
sets differ. `steep stats` also emits the already-known internal `Rush::Status` compatibility
message while exiting successfully, so its diagnostic stream must be retained with the aggregate.

## Enforced ratchet

`bundle exec rake sorbet` now performs the normal type check and coverage check in one raw-binary
pass. It exports Sorbet's internal counters and file table to temporary JSON, replays diagnostics,
then checks two separately reviewed files:

- `sorbet/coverage_baseline.json` records the exact Sorbet version, every input path plus sigil, and
  the observed counters. Version or path/sigil drift fails and therefore requires explicit review.
- `sorbet/coverage_budgets.json` owns pass/fail policy: after the thirteenth `rush-435.7` root slice, at
  most 731 untyped sends and an exact rational minimum ratio of 12,464 / 13,195. Both checks apply, so codebase growth cannot hide a
  larger absolute gap and deleting typed sends cannot preserve the gap while lowering the ratio.

The baseline observations are evidence, not a second implicit budget. The explicit workflow is:

```sh
bundle exec rake sorbet
bundle exec rake sorbet:coverage:record # updates scope/observations only; never budgets
```

After a real improvement, lower `maximum_untyped_sends` and raise the rational ratio in the budget
file in the same reviewed slice. Run `record` only when a sigil/path or Sorbet version deliberately
changes; for a Sorbet upgrade, retain old/new results side by side in the journal before accepting
the new baseline. Never loosen a budget merely because `record` observed a regression.

Default-gate cost is negligible. Eight interleaved local process cohorts measured the old raw type
check at 63.3 ms median and the version + metrics/file-table run at 70.5 ms: +7.2 ms before the
unchanged rake startup, far below the gate's existing multi-second Sorbet lane and fully shadowed by
RSpec/allocation work. The ratchet therefore stays in the default `sorbet` task rather than becoming
an opt-in alarm.

The timing probe used Python `time.perf_counter`, alternated which side ran first, discarded all
output, and timed these argv shapes: `sorbet`; versus `sorbet --version` followed by
`sorbet --track-untyped=everywhere --metrics-file=<tmp> --print=file-table-json:<tmp>`. Raw old
samples were 59.9, 62.5, 62.8, 67.0, 68.2, 61.9, 63.9, 65.5 ms; new samples were 95.8, 89.2,
66.9, 69.4, 69.1, 123.2, 70.6, 70.4 ms. The medians, not the noisy maxima, support the gate choice.

### Ratchet progress

| Slice | Change | Typed / total sends | Ratio | Untyped sends | Untyped usages |
|---|---|---:|---:|---:|---:|
| 19l | Inventory baseline | 11,085 / 12,401 | 89.39% | 1,316 | 1,669 |
| 19n | `PrintfFormatter` checked end to end | 11,191 / 12,503 | 89.51% | 1,312 | 1,666 |
| 19o | `ResourceLimits` checked end to end | 11,236 / 12,537 | 89.62% | 1,301 | 1,661 |
| 19p | `ProcessControl` checked end to end | 11,404 / 12,690 | 89.87% | 1,286 | 1,647 |
| 19q | `SystemCalls` checked end to end | 11,595 / 12,878 | 90.04% | 1,283 | 1,647 |
| 19r | POSIX `printf` numeric conversion | 11,659 / 12,942 | 90.09% | 1,283 | 1,647 |
| 19s | `ParserSupport` checked; generated Racc bounded | 11,816 / 13,095 | 90.23% | 1,279 | 1,642 |
| 19t | `ulimit` Data/state roots | 11,886 / 13,123 | 90.57% | 1,237 | 1,589 |
| 19u | `test` evaluator declarations | 12,074 / 13,218 | 91.35% | 1,144 | 1,495 |
| 19v | `UmaskMode` constant/ivar roots | 12,103 / 13,218 | 91.56% | 1,115 | 1,451 |
| 19w | shell-parameter state/delegate roots | 12,151 / 13,203 | 92.03% | 1,052 | 1,374 |
| 19x | `Environment` storage/block roots | 12,181 / 13,210 | 92.21% | 1,029 | 1,345 |
| 19y | getopts Data/state/variant roots | 12,224 / 13,213 | 92.51% | 989 | 1,286 |
| 19z | `ShellVariables` Forwardable surface | 12,215 / 13,152 | 92.88% | 937 | 1,260 |
| 19aa | remaining non-AST Data roots | 12,232 / 13,152 | 93.00% | 920 | 1,232 |
| 19ab | `Positional` Forwardable surface | 12,240 / 13,152 | 93.07% | 912 | 1,229 |
| 19ac | lexer token/value boundary and word readers | 12,269 / 13,127 | 93.46% | 858 | 1,162 |
| 19ad | `WordSegment` closed payload union | 12,233 / 13,087 | 93.47% | 854 | 1,160 |
| 19ae | AST reader, redirect-target and `CommandText` dispatch contracts | 12,419 / 13,194 | 94.13% | 775 | 1,073 |
| 19af | `test` callable-body and grammar-state roots | 12,464 / 13,195 | 94.46% | 731 | 986 |

## Material usage clusters

For this inventory, a material destination cluster is a typed-true file with at least 15 normal
untyped usages. The 37 files below account for 1,103 / 1,669 usages (66.1%). The remaining tail is
17 files with 10–14 usages (207 total) and 93 files with 1–9 (359 total).

The category is a root-cause lead from the forced-strong origins and source audit, not a promised
counter yield:

- **declaration** — missing method signatures, undeclared ivar types, or untyped `Data` readers;
- **variant** — a real heterogeneous domain value that needs a bounded union/protocol;
- **dynamic** — a callable/reflective registry whose dispatch erases a type;
- **native** — a Ruby C API, syscall, Fiddle, stream, or project RBI boundary;
- **Racc** — lexer token / generated-parser semantic-stack boundary.

| Usages | Destination | Root-cause leads |
|---:|---|---|
| 90 | `lib/rush/builtins/ulimit.rb` | declaration, native |
| 72 | `lib/rush/builtins/test_operators.rb` | declaration, dynamic |
| 63 | `lib/rush/builtins/test_grammar.rb` | declaration |
| 57 | `lib/rush/lexer.rb` | declaration, variant, Racc |
| 51 | `lib/rush/command_text.rb` | declaration, variant, dynamic |
| 47 | `lib/rush/getopts_parser.rb` | declaration, variant |
| 44 | `lib/rush/umask_mode.rb` | declaration, dynamic |
| 40 | `lib/rush/builtins/test_expr.rb` | declaration |
| 36 | `lib/rush/shell_parameters.rb` | declaration, variant |
| 35 | `lib/rush/expansion/parameter_expander.rb` | declaration |
| 30 | `lib/rush/expansion/ifs_scanner.rb` | declaration |
| 30 | `lib/rush/shell_pattern.rb` | declaration |
| 29 | `lib/rush/environment.rb` | declaration, variant |
| 28 | `lib/rush/lexer/lex_state.rb` | declaration, variant |
| 28 | `lib/rush/posix_pattern.rb` | declaration |
| 26 | `lib/rush/lexer/quoted_word.rb` | declaration |
| 26 | `lib/rush/shell_state.rb` | declaration |
| 24 | `lib/rush/shell_variables.rb` | declaration |
| 23 | `lib/rush/lexer/quote_skips.rb` | declaration, variant |
| 22 | `lib/rush/builtins/cd.rb` | declaration |
| 22 | `lib/rush/lexer/heredoc_body.rb` | declaration |
| 21 | `lib/rush/exit_trap.rb` | declaration |
| 20 | `lib/rush/executor.rb` | declaration, variant |
| 20 | `lib/rush/expansion/parameter_forms.rb` | declaration, dynamic |
| 20 | `lib/rush/here_doc.rb` | declaration, variant |
| 19 | `lib/rush/bracket_scanner.rb` | declaration |
| 18 | `lib/rush/expansion/ifs.rb` | declaration |
| 18 | `lib/rush/lexer/paren_regions.rb` | declaration |
| 18 | `lib/rush/program_reader.rb` | declaration, Racc |
| 17 | `lib/rush/system_calls/collation.rb` | native, dynamic |
| 16 | `lib/rush/getopts_state.rb` | declaration |
| 16 | `lib/rush/lexer/word_scanner.rb` | declaration |
| 16 | `lib/rush/scope.rb` | declaration, variant |
| 16 | `lib/rush/trap_runner.rb` | declaration, variant |
| 15 | `lib/rush/ast/word.rb` | declaration, variant |
| 15 | `lib/rush/builtins/read_input.rb` | native, variant |
| 15 | `lib/rush/expansion/arithmetic/parser.rb` | declaration, variant |

### Root-cause ledger

1. **No handwritten unchecked body remains.** The inventory forced-strong probe found 156 hidden
   diagnostics across ParserSupport (54) and the four formatter/syscall bodies (102). Slices
   `rush-435.3` through `.6` raised the four tractable files; `rush-435.8` then checked every
   ParserSupport factory through exact aliases and a generated-host RBI. Its sole semantic-stack
   result crosses one `T.cast` to the grammar-proven `AST::List` start symbol.

2. **Generated Racc glue.** `lib/rush/parser.rb` has no sigil, is generated and is ignored by both
   type-checker gates. Forced strong finds one send-shaped location there. `Lexer` and
   `ParserSupport` now model the same exact terminal/value union on their two sides of the generated
   host, while the parser RBI exposes typed construction, the `AST::List` start result, and only the
   two generated host methods it consumes. The generated table/semantic stack remains a bounded
   adapter, not permission to type or patch generated code by hand.

3. **Missing ordinary declarations.** Slice 19u typed every method in `TestOperators`,
   `TestGrammar`, and `TestExpr`; Slice 19af then declared TestGrammar's four storage ivars and
   replaced its checker-internal pattern-match residue, taking its forced-strong diagnostics to zero.
   Slice 19x made Environment's four storage ivars and two block-return contracts exact. Slice 19ae
   completed every ordinary AST node reader feeding execution and
   rendering; their existing exact RBS contracts now have matching Sorbet signatures. Many remaining
   typed-true classes still expose ordinary open roots, so `rush-435.7` should continue with shared
   declarations and remeasure before changing dispatch architecture.

4. **Untyped value readers and bounded variants.** Slice 19t gave the three `ulimit` values exact
   Data-reader/constructor shims and replaced its heterogeneous mutable hash with a typed state
   object; Slice 19w did the same for `ShellProcessIds` and the three Forwardable reads feeding shell
   parameters, and Slice 19ab completed Positional's array-compatible reader surface. Slice 19y modeled getopts' Result/Option values and separated its keep-OPTARG control
   bit; Slice 19z completed ShellVariables' exact Environment/Scope facade. Slice 19aa completes the
   non-AST Data set with `cd`, `HereDoc` and `ExitTrap` contracts: only generated definition-site
   diagnostics remain, not open consumers. Slice 19ac closes the lexer token kind/value pair and the
   `AST::Word` reader boundary; Slice 19ad then closed the `AST::WordSegment` payload domain: the
   four concrete segments form a named union, and the payload type member carries an honest
   `String | ParamRef` bound. Slice 19ae closes `Redirect#target` as the named `Word | HereDoc`
   variant and removes its renderer cast. The remaining explicit opens include logical IO streams
   and generic block returns. These should become named unions or value contracts where consumers discriminate them;
   broad casts would only move the counter.

5. **Dynamic registries.** `CommandText`, parameter forms, redirection, and test operators use
   reflective or callable tables. Slice 19v made `UmaskMode`'s registries and mutable bit field exact;
   its reflective dispatch remains, but the file now has zero strong 7018 diagnostics. Slice 19ae
   first typed the complete AST reader surface, then replaced `CommandText`'s residual
   `Method#call` erasure with a small exact-class dispatcher; `CommandText` now likewise has zero
   strong 7018 diagnostics without casts. Slice 19af gives TestOperators' three callable kinds named
   proc contracts and annotates each strict lambda at construction for both checkers, so all 26
   bodies are checked with no runtime adapter and that file also reaches zero. Other registries
   should follow that order: sign values first,
   and replace reflection only when an actual residual root remains.

6. **System and native ports.** Resource, job-control, signal, redirect ownership and interactive
   contracts are now explicit in the implementation/RBS/Sorbet surfaces; the close-only logical
   stream parameter remains mirrored and open because Sorbet lacks RBS structural protocols.
   Process.spawn and exec retain exactly two narrow receiver escapes because Sorbet rejects Ruby's dynamically sized
   non-terminal argv splat; their option keys and return contracts remain checked. Their flat option
   values are the same logical-stream seam, not a separate tractable collection, so wrapping the hash
   merely to hide its stream values is not a typing gain. The Fiddle collation backend still has an
   intentionally dynamic callable/pointer table, which
   `rush-435.7` must retain in the measured native ledger.

The explicit source ledger currently contains 73 `T.untyped` declaration lines across production
and project RBIs (27 production files and four RBI files), plus two `T.unsafe` and six `T.cast`
lines. These are review targets, not automatically defects: Fiddle pointers and logical IO streams, for example, may
remain honestly open after the ordinary roots are removed.

## Target and prioritized plan

The epic target is a **stretch target of at least 95% typed sends**, with an explicit final-ceiling
escape only for measured native/Racc/variant residue. After the thirteenth `rush-435.7` root slice, at
the normal denominator:

- `ceil(13,195 × 0.95) = 12,536` typed sends;
- this needs 72 additional typed sends;
- no more than 659 sends may remain untyped;
- that removes 9.8% of the current 731-send gap.

Forcing the remaining no-sigil generated parser changes the denominator, so the fixed calculation
is not the whole plan. Forcing every current input to `typed: true` without changing source produces a
conservative scope envelope of 12,481 / 13,316 typed sends (93.73%, gap 835). At that denominator
95% is 12,651 typed sends: +170, leaving at most 665 untyped, a 20.4% gap reduction. The current
location probe finds 548 concrete send-shaped diagnostics (547 outside generated parser), with 202
concentrated in 14 files having at least ten each. These diagnostics still do not map one-for-one to
the counter, but they demonstrate a candidate send surface larger than the required gain and tie it
to the ordinary declaration, registry and bounded-variant roots above.

That makes 95% a defensible **target**, not a demonstrated ceiling: it requires resolving most of
the measured send-shaped surface, while the known hard native/Racc subset must remain narrow. If
precise boundaries leave more than 665 sends untyped at the expanded scope, `rush-435.9` must publish
the lower honest ceiling and residual arithmetic rather than add escapes.

Work order:

1. **`rush-435.2`** — ratchet the fixed normal scope, typed-send ratio, and absolute untyped-send
   count; a Sorbet or scope change requires an explicit side-by-side baseline reset.
2. **`rush-435.3`** — type PrintfFormatter's 40 forced-strong sites without weakening scanner and
   numeric-error behavior.
3. **`rush-435.4`** — type ResourceLimits and the public resource API feeding the 90-usage ulimit
   destination cluster.
4. **`rush-435.5`** — type ProcessControl's 35 sites and its wait/fork/tty/ioctl shapes.
5. **`rush-435.6`** — type the remaining SystemCalls body's 18 sites and complete its caller-facing
   RBI without global option/stream widening.
6. **`rush-435.8`** — adjudicated: ParserSupport is checked end to end; the generated parser remains
   no-sigil, with one explicit semantic-stack result cast and one unused error-stack parameter.
7. **`rush-435.7`** — remeasure, then sweep shared typed-true roots in this order: missing method and
   ivar declarations; `Data`/bounded variants; loose project RBIs; registries; native residue.
8. **`rush-435.9`** — publish the final numerator/denominator and either demonstrate 95% or justify
   the measured ceiling.

Anti-gaming rules for every slice:

- track both the ratio and absolute untyped-send gap;
- keep Sorbet version and observed inputs fixed, or reset with old/new results side by side;
- do not exclude parser/source or add trivial typed inputs to alter the denominator;
- do not count `T.unsafe`, broad `T.untyped`, loose RBIs, or casts as precision gains;
- require raised sigils to check implementation bodies;
- keep Steep, behavioral, mutation/allocation where relevant, and the full quality gate green.

## Historical comparison

The 2026-07-12 snapshot at parent revision `327c081` recorded 10,598 / 11,891 typed sends
(89.13%), leaving 1,293 untyped sends. The refreshed baseline has 487 more typed sends but 510 more
total sends, so the absolute gap is **23 sends larger** despite the ratio rising by about 0.26
percentage points. No implementation-typing improvement is inferred from that movement.
