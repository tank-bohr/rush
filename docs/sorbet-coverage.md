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

# Planning envelope for the five false bodies plus the no-sigil parser. This exits 100
# because it reveals their existing type errors; the counters are still emitted.
status=0
"$bin" --typed=true --track-untyped=everywhere --counters \
  > /tmp/rush-sorbet-forced-true-counters.txt 2>&1 || status=$?
test "$status" -eq 100

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
false bucket. The parser remains in input accounting even though its diagnostics are ignored.
The extensionless `exe/rush` is configured through `--dir ./exe` but is absent from the file table,
so it is outside this baseline. A later scope change must record a side-by-side baseline rather than
silently moving the denominator.

Steep checks 203 implementation files under `lib` (all 204 Ruby files except the generated parser),
not Sorbet's four RBI inputs or the executable. Its current receiver-based ledger is 11,253 / 11,276
typed calls (99.80%). That percentage is not comparable to Sorbet's send metric; even their input
sets differ. `steep stats` also emits the already-known internal `Rush::Status` compatibility
message while exiting successfully, so its diagnostic stream must be retained with the aggregate.

## Enforced ratchet

`bundle exec rake sorbet` now performs the normal type check and coverage check in one raw-binary
pass. It exports Sorbet's internal counters and file table to temporary JSON, replays diagnostics,
then checks two separately reviewed files:

- `sorbet/coverage_baseline.json` records the exact Sorbet version, every input path plus sigil, and
  the observed counters. Version or path/sigil drift fails and therefore requires explicit review.
- `sorbet/coverage_budgets.json` owns pass/fail policy: after `rush-435.4`, at most 1,301 untyped
  sends and an exact rational minimum ratio of 11,236 / 12,537. Both checks apply, so codebase growth cannot hide a
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

1. **Five handwritten unchecked bodies.** The forced-strong probe reports 156 diagnostics that the
   normal file table cannot see: `ParserSupport` 54, `PrintfFormatter` 40, `ProcessControl` 35,
   `SystemCalls` 18, and `ResourceLimits` 9. Their callers can still receive typed public surfaces,
   but the implementations themselves are not checked. `rush-435.3` through `.6` own the four
   tractable formatter/syscall files; `rush-435.8` adjudicates ParserSupport rather than claiming a
   sigil win around an open Racc stack.

2. **Generated Racc glue.** `lib/rush/parser.rb` has no sigil, is generated and is ignored by both
   type-checker gates. Forced strong finds two locations there. `Lexer` currently exports
   `[T.untyped, T.untyped]` token pairs and the parser RBI exposes only construction and `#parse`.
   This is a bounded adapter/semantic-value decision for `rush-435.8`, not permission to type the
   generated file by hand.

3. **Missing ordinary declarations.** The biggest pure-Ruby cluster is not inherently dynamic:
   `TestOperators`, `TestGrammar`, and `TestExpr` contain typed-true methods without inline
   signatures, while many typed-true classes assign ivars without `T.let`. Sorbet therefore
   propagates untyped through otherwise ordinary calls. `rush-435.7` should add shared root
   declarations first and remeasure before changing dispatch architecture.

4. **Untyped value readers and bounded variants.** Non-AST `Data.define` values in `ulimit`,
   `getopts`, `cd`, `HereDoc`, `ExitTrap`, and `ShellState` expose untyped readers. Other explicit
   opens are domain variants: lexer token kind/value, `AST::WordSegment` payloads, redirect targets,
   getopts' `String | :keep | nil`, logical IO streams, and generic block returns. These should become
   named unions or value contracts where consumers discriminate them; broad casts would only move
   the counter.

5. **Dynamic registries.** `CommandText`, `UmaskMode`, parameter forms, redirection, and test
   operators use reflective or callable tables. Some lambdas are already precisely `T.let`-typed,
   so the first move is to sign their module methods and values. Replace reflection only when a
   residual root remains; do not turn a registry into a case statement solely for the metric.

6. **System and native ports.** The `SystemCalls` RBI omits resource-limit and job-control methods and
   keeps spawn/exec options, signals and redirect streams open. The Fiddle collation backend has an
   intentionally dynamic callable/pointer table. `rush-435.4`–`.6` should normalize platform return
   shapes and add narrow project RBIs; `rush-435.7` must retain a small native ledger for values
   Sorbet cannot honestly model.

The explicit source ledger currently contains 111 `T.untyped` declaration lines across production
and project RBIs (37 production files and three RBI files), plus three `T.unsafe` lines. These are
review targets, not automatically defects: Fiddle pointers and logical IO streams, for example, may
remain honestly open after the ordinary roots are removed.

## Target and prioritized plan

The epic target is a **stretch target of at least 95% typed sends**, with an explicit final-ceiling
escape only for measured native/Racc/variant residue. After `rush-435.4`, at the normal denominator:

- `ceil(12,537 × 0.95) = 11,911` typed sends;
- this needs 675 additional typed sends;
- no more than 626 sends may remain untyped;
- that removes 51.9% of the current 1,301-send gap.

Raising the remaining false/no-sigil bodies changes the denominator, so the fixed calculation is not
the whole plan. Forcing every current input to `typed: true` without changing source produces a
conservative scope envelope of 11,404 / 12,862 typed sends (88.66%, gap 1,458). At that denominator
95% is 12,219 typed sends: +815, leaving at most 643 untyped, a 55.9% gap reduction. The current
location probe finds 912 concrete send-shaped diagnostics (911 outside generated parser), with 511
concentrated in 27 files having at least ten each. These diagnostics still do not map one-for-one to
the counter, but they demonstrate a candidate send surface larger than the required gain and tie it
to the ordinary declaration, false-body, registry and bounded-variant roots above.

That makes 95% a defensible **target**, not a demonstrated ceiling: it requires resolving most of
the measured send-shaped surface, while the known hard native/Racc subset must remain narrow. If
precise boundaries leave more than 642 sends untyped at the expanded scope, `rush-435.9` must publish
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
6. **`rush-435.8`** — probe the generated parser adapter and keep ParserSupport false if a true sigil
   would merely wrap semantic-stack `T.untyped`.
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
