# Forked execution modes and lifecycle ordering

## Decision

Keep four explicit forked-shell modes rather than hiding them behind one conditional-heavy child
runner:

1. foreground subshell `( list )`;
2. one child per multi-stage pipeline stage;
3. asynchronous list `list &`;
4. command substitution `$(list)` / backticks.

They share `Executor#enter_subshell`, but their work immediately before and after entry is
semantically different. The ordering below is part of the runtime contract. This record describes
the shipped behavior before any extraction; it does not introduce a new lifecycle abstraction.

## Shared subshell entry

`Executor#enter_subshell` always performs these transitions in order:

1. `TrapRunner#reset_caught_for_subshell` creates a fresh one-shot EXIT lifecycle, clears pending
   caught signals, drops interactive/job-control base handlers to OS defaults, and resets caught
   traps while preserving ignored traps;
2. `JobTable#enter_subshell` keeps parent jobs only as inherited display copies, clears the foreign
   status stash, drops root-shell/terminal/monitor ownership, and preserves an already-armed pipeline
   stop relay.

Consequently a forked environment may still list inherited jobs and `$!`, but it cannot wait for
those parent children. `JobTable` remains the sole reaper in every environment.

## Mode matrix

| Mode | Parent launch and completion | Child work before entry | Entry count | IO and signal policy after entry | Errexit context | Error and EXIT policy |
|---|---|---|---:|---|---|---|
| Foreground `( list )` | `JobControl#launch`; grouped only under monitor, with double `setpgid`; parent foreground-waits, adopts stops, reports a signal | under monitor: child `setpgid` and leader tty handover → entry | 1 | inherited base IO; caught traps reset, ignored traps inherited | inherits the caller's dynamic tested/untested state | `ErrorPolicy(:subshell)` maps child control/errors to status; EXIT runs after mapping and may override |
| Pipeline stage | stages fork sequentially; under monitor they join stage 0's group via double `setpgid`; parent closes all pipe ends, waits for every pid, then applies normal/pipefail verdict | optional child grouping/leader tty handover → close unused pipe ends → arm stop relay → bind stage IO | 1 | stdin/stdout overlaid by adjacent pipes; armed relay survives monitor-dropping entry | inherits the pipeline's dynamic context, including tested contexts | delegates to `SubshellRunner#run_body`, therefore the same mapping and EXIT lifecycle |
| Background, monitor off | plain `launch_background`; parent records `$!` and job entry and immediately returns success | snapshot `monitored?` → first entry | 2 | raw INT/QUIT `SIG_IGN` and stdin `/dev/null` are both installed between entries (their mutual order is not a contract); command redirects may replace stdin | inherits the tested context established for an async list | delegates to `SubshellRunner`; EXIT is child-local |
| Background, monitor on | grouped with double `setpgid`, never tty handover; parent still returns launch success | child `setpgid` → snapshot `monitored?` → first entry | 2 | keep inherited stdin and do not force INT/QUIT ignores → second entry → body | same async tested context | delegates to `SubshellRunner`; EXIT is child-local |
| Command substitution | raw `SystemCalls#fork`, deliberately outside `JobControl`; parent closes writer, reads fully before waiting, reports signal, records `cmd_sub_status`, strips trailing newlines | bind stdout to pipe writer | 1 | inherited stdin, stdout pipe; ordinary subshell trap/job reset | explicitly `ErrexitContext#untested`, regardless of caller | catches only `ExitSignal`/`ReturnSignal`; then runs local EXIT. Other operational errors are not normalized by `SubshellRunner` and currently escape `capture` to the process boundary |

A single-stage pipeline is not a forked pipeline mode: `AST::Pipeline` executes it in-process.
Every stage of a multi-stage pipeline is forked, including compound commands and functions.

## Load-bearing child sequence

```mermaid
sequenceDiagram
    participant P as Parent
    participant C as Forked child
    participant E as enter_subshell
    participant B as Shell body
    participant X as EXIT / termination boundary

    P->>C: fork (job modes use JobControl; command substitution uses raw fork)
    opt monitor-grouped launch (never command substitution)
        par child half of double setpgid
            C->>C: setpgid; foreground leader may take tty
        and parent half of double setpgid
            P->>P: setpgid(child, group)
        end
    end
    alt explicit subshell
        C->>E: enter once
    else pipeline stage
        C->>C: close unused pipes
        C->>C: arm stop relay
        C->>C: bind stage IO
        C->>E: enter once (relay survives)
    else background list
        C->>C: snapshot monitored?
        C->>E: first entry (monitor machinery drops)
        opt snapshot said unmonitored
            par post-entry isolation
                C->>C: INT/QUIT = SIG_IGN
            and post-entry isolation
                C->>C: stdin = /dev/null
            end
        end
        C->>E: second entry
    else command substitution
        C->>C: bind stdout writer
        C->>E: enter once
        C->>C: force errexit untested
    end
    E-->>C: entry complete
    C->>B: execute in the mode's errexit/error context
    alt normal result or SubshellRunner-resolved error
        B->>X: resolved status, then local EXIT
    else command-substitution operational error
        B->>X: escape capture to process boundary; skip local EXIT
    end
    X-->>P: child termination (exit! or uncaught process-boundary error)
```

Parent-side completion is intentionally not shared:

- subshell and pipeline use `JobControl#foreground`; terminal ownership surrounds the complete wait,
  then stopped-job adoption runs before the call returns;
- background launch does not wait at all;
- command substitution reads the pipe before waiting so a pipe-filling child cannot deadlock, then
  publishes the child's status on the command-substitution channel rather than directly changing the
  enclosing command's `$?`.

## Why the background mode enters twice

`BackgroundRunner#isolate` must read `monitored?` before the first entry because entry deliberately
turns root-only monitor machinery off. It must enter before installing unmonitored INT/QUIT ignores
because dropping inherited interactive base handlers afterward would overwrite those ignores.
`SubshellRunner#run_body` then performs its normal entry again.

That immediate repeat is intentionally harmless **at this seam**: isolation creates no
reset-sensitive shell state between calls — no shell body, child job, pending signal, caught trap or
child EXIT action. Raw signal dispositions and stdin are changed, but the second entry does not reset
them. This is not a general promise that
`enter_subshell` may be called after child lifecycle state exists; entry always replaces EXIT state
and clears pending signals. Any work inserted between the two calls must re-evaluate this design.

## Exception-boundary asymmetry

Subshell, pipeline-stage, and background bodies all pass through `SubshellRunner`:

- exit and uncaught return become their requested code;
- stray loop control uses the already-published child status;
- fatal parse/expansion/readonly/special-builtin failures are diagnosed and become 2;
- every named `Rush::Error` exact class has an explicit subshell row; adding a new class without a
  row fails classification rather than inheriting a catch-all policy.

Command substitution has a narrower boundary: it catches exit and return only. Do not replace this
with `SubshellRunner` or a shared broad rescue until operational-error behavior has been separately
adjudicated against POSIX and dash. Setup failures before the body boundary (pipe setup, background
isolation, stage fd setup) likewise remain outside body error mapping and EXIT handling.

## Characterization and differential evidence

The ordering contract is pinned directly by:

- `spec/rush/executor_forked_execution_lifecycle_spec.rb` — entry/body/EXIT order, pipeline
  close→relay→IO→entry order, background monitor snapshot and double entry, command-substitution
  IO→entry→untested→EXIT order, and immediate-entry idempotence;
- `spec/rush/subshell_runner_spec.rb` — parent launch/wait/signal behavior and child status, trap,
  loop-control, fatal-error, and EXIT semantics;
- `spec/rush/pipeline_runner_spec.rb` — grouping, terminal lifetime, pipe ownership, relay survival,
  stage IO, child errors, and stage EXIT;
- `spec/rush/background_runner_spec.rb` — launch-only parent behavior and the monitored/unmonitored
  stdin plus INT/QUIT matrix;
- `spec/rush/expansion/command_substitution_spec.rb` — read/wait/status publication, fresh untested
  context, inherited-trap reset, return/exit, and local EXIT;
- `spec/rush/job_table_spec.rb` and `spec/rush/trap_runner_spec.rb` — the two halves of repeated
  `enter_subshell` and relay preservation.

Real process boundaries remain differential responsibilities. The main corpora are:

- `spec/integration/differential/execution_control_spec.rb` for subshell/pipeline/EXIT/errexit;
- `spec/integration/differential/background_wait_spec.rb` for async isolation and inherited jobs;
- `spec/integration/differential/job_control_spec.rb` for process groups, root-only monitor behavior,
  and command substitution remaining in the shell group;
- `spec/integration/differential/traps_signals_spec.rb` for caught-signal and wait interactions.

## Extraction and revisit triggers

Do not extract a common child runner merely because all four modes fork. Revisit only when one of
these concrete triggers fires:

1. two modes acquire another identical ordered phase beyond entry and EXIT, enough to remove real
   duplication without adding mode flags;
2. `enter_subshell` gains a new side effect, or any work is inserted between background isolation's
   first entry and `SubshellRunner`'s second entry;
3. launch/grouping becomes deferred, so the monitor snapshot can change between policy choice and
   fork, or pipeline stages can mutate monitor state between launches;
4. stop-relay ownership moves — relay arming must remain before monitor-dropping entry;
5. command-substitution operational errors are POSIX/dash-adjudicated and can safely share an error
   boundary;
6. a no-fork/tail-exec optimization changes which environment owns jobs, traps, EXIT, or reaping;
7. the IO model changes enough that pipe binding/closure must move across the entry boundary.

If extraction is triggered, model explicit phases (pre-entry snapshot/hook, entry, post-entry setup,
IO context, errexit context, error policy, EXIT, parent completion). Do not split `JobTable`'s single
wait ownership, reopen the real-fd migration, or create a universal resolver as collateral work.
