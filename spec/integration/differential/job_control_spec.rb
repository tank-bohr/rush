# frozen_string_literal: true

require 'timeout'

# Job control, the terminal-free half of `set -m` (rush-mv8.2): the monitor
# flag in $- (and its refusal in an interactive shell without a tty), the
# shell's SIGTSTP ignore and its interplay with user traps, and process-group
# placement — every forked job (background list, pipeline, subshell, external
# command) becomes its own group with the first process as leader, while
# command substitution and non-root (forked) shells never group. All probed
# against dash 0.5.13 off-tty; the pgid predicates compare groups by equality
# so the output is deterministic. TSTP lines run under Timeout: the failure
# mode of a broken disposition is a stopped shell, which would otherwise hang
# the suite instead of failing it.
RSpec.describe 'rush vs dash (differential job-control corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  corpus = [
    # the m flag: set -m/+m, the -o monitor long form, $- order, inheritance
    'set -m; echo "[$-]"',
    'set -o monitor; echo "[$-]"',
    'set -m; set +m; echo "[$-]"',
    'set -m; set +o monitor; echo "[$-]"',
    'set -m; ( echo "[$-]" ); true',
    'set -m; set -e; set -u; set -x; set -a; set -C; set -f; set -v; echo "$-"',
    # process groups: a background job leaves the shell's group...
    'set -m; sleep 5 & a=$(ps -o pgid= -p $$ | tr -d " "); b=$(ps -o pgid= -p $! | tr -d " "); ' \
    'if [ "$a" = "$b" ]; then echo same; else echo diff; fi; kill $!',
    'sleep 5 & a=$(ps -o pgid= -p $$ | tr -d " "); b=$(ps -o pgid= -p $! | tr -d " "); ' \
    'if [ "$a" = "$b" ]; then echo same; else echo diff; fi; kill $!',
    # ...a foreground pipeline's stages share one fresh group (compared by
    # pgid, not the leader's pid: dash EV_EXIT-execs a tail command in place
    # while rush forks it, so stage pids differ by design until rush-mv8.7;
    # leader identity is pinned by the PipelineRunner unit spec instead)...
    'set -m; shell=$(ps -o pgid= -p $$ | tr -d " "); ' \
    "sh -c 'ps -o pgid= -p $$' | { read lead; lead=$(echo $lead); " \
    "pg=$(sh -c 'ps -o pgid= -p $$' | tr -d \" \"); " \
    'if [ "$lead" = "$pg" ] && [ "$lead" != "$shell" ]; then echo grouped; else echo apart; fi; }',
    'shell=$(ps -o pgid= -p $$ | tr -d " "); ' \
    "sh -c 'ps -o pgid= -p $$' | { read lead; lead=$(echo $lead); " \
    "pg=$(sh -c 'ps -o pgid= -p $$' | tr -d \" \"); " \
    'if [ "$lead" = "$pg" ] && [ "$lead" != "$shell" ]; then echo grouped; else echo apart; fi; }',
    # ...a foreground external command leads its own group...
    "set -m; sh -c 'pg=$(ps -o pgid= -p $$ | tr -d \" \"); " \
    'if [ "$pg" = "$$" ]; then echo own; else echo shared; fi\'; true',
    "sh -c 'pg=$(ps -o pgid= -p $$ | tr -d \" \"); " \
    'if [ "$pg" = "$$" ]; then echo own; else echo shared; fi\'; true',
    # ...while command substitution stays in the shell's group, and a forked
    # child (here a subshell) has the machinery off entirely (root shell only)
    'set -m; a=$(ps -o pgid= -p $$ | tr -d " "); b=$(sh -c \'ps -o pgid= -p $$\' | tr -d " "); ' \
    'if [ "$a" = "$b" ]; then echo same; else echo diff; fi',
    'set -m; ( sleep 5 & a=$(ps -o pgid= -p $! | tr -d " "); b=$(sh -c \'ps -o pgid= -p $$\' | tr -d " "); ' \
    'if [ "$a" = "$b" ]; then echo same; else echo diff; fi; kill $! ); true',
    # a monitored background job keeps default SIGINT (POSIX 2.11 ignores
    # apply only without job control; the child signals itself, so no race)
    "set -m; sh -c 'kill -INT $$; echo alive' & wait $!; echo st=$?",
    "sh -c 'kill -INT $$; echo alive' & wait $!; echo st=$?"
  ].freeze

  corpus.each.with_index(1) do |snippet, index|
    id = format('jc-%03d', index)

    it "#{id}: matches dash for: #{snippet}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end

  # The shell's own SIGTSTP under -m: ignored as a base disposition — a user
  # trap wins in either order, `trap -` falls back to the ignore, not the OS
  # default. (`set +m` restoring the stopping default stays out of the corpus:
  # both shells would stop and never exit.)
  tstp = [
    'set -m; kill -TSTP $$; echo alive',
    'set -m; trap "echo got" TSTP; kill -TSTP $$; echo alive',
    'trap "echo got" TSTP; set -m; kill -TSTP $$; echo alive',
    'set -m; trap "echo x" TSTP; trap - TSTP; kill -TSTP $$; echo alive'
  ].freeze

  describe 'the shell-side SIGTSTP ignore' do
    tstp.each.with_index(1) do |snippet, index|
      id = format('jc-tstp-%03d', index)

      it "#{id}: matches dash under Timeout for: #{snippet}" do
        Timeout.timeout(10) { expect(rush(snippet)).to eq(dash(snippet)) }
      end
    end
  end

  # Invocation forms: -m on the command line, and the interactive refusal —
  # dash drops m from $- when -i has no tty, at startup and at runtime alike.
  argv_corpus = [
    [['-m', '-c', 'echo "[$-]"'], nil],
    [['-o', 'monitor', '-c', 'echo "[$-]"'], nil],
    [['-s', '-m'], "echo \"[$-]\"\n"],
    [['-s', '-i', '-m'], "echo \"[$-]\"\n"],
    [['-s', '-i'], "set -m; echo \"[$-]\"\n"]
  ].freeze

  argv_corpus.each do |args, input|
    it "matches dash for `sh #{args.join(' ')}`#{' reading stdin' if input}" do
      expect(rush_argv(args, input)).to eq(dash_argv(args, input))
    end
  end

  it 'jc-tstp-cli: matches dash for -m on the command line ignoring TSTP' do
    args = ['-m', '-c', 'kill -TSTP $$; echo alive']
    Timeout.timeout(10) { expect(rush_argv(args)).to eq(dash_argv(args)) }
  end

  it 'jc-inp: a monitored background job keeps the shell stdin (no /dev/null redirect)' do
    snippet = 'set -m; cat & wait $!; echo st=$?'
    expect(rush(snippet, "hi\n")).to eq(dash(snippet, "hi\n"))
  end

  # Stopped jobs off-tty (rush-mv8.4): monitor waits are WUNTRACED, so a
  # foreground job that stops itself hands 148 back and parks as a Stopped
  # entry — the script continues past it, wait answers immediately and
  # repeatably, jobs keeps listing it (projected through sed: the command
  # text column arrives with rush-mv8.6), and exit is refused exactly once.
  # Pipeline stops are IN since the stage stop relay (rush-l4o): a stage
  # of a monitor-mode job re-raises a member's stop onto itself, so the
  # parent's WUNTRACED wait parks the whole job exactly where dash — whose
  # exec'd simple stages stop directly — parks it. Compound stages stay
  # out: dash (and bash) genuinely hang there, the relay answers — the
  # journal records the divergence. Everything under Timeout: the failure
  # mode of a missing WUNTRACED is a hung shell. The stray stopped
  # children die on their own (kernel orphaned-pgroup HUP+CONT) only when
  # the dead shell's children re-parent outside their session — hence the
  # _in_session runners; a container's same-session pid 1 otherwise keeps
  # the stray alive holding the capture pipes (rush-erq).
  stopped = [
    "set -m; sh -c 'exit 5' | sh -c 'kill -TSTP $$'; echo st:$?; kill -9 %1; echo done",
    "set -m; sh -c 'kill -TSTP $$' | sh -c 'exit 5'; echo st:$?; kill -9 %1; echo done",
    "set -m; sh -c 'kill -TSTP $$' | sh -c 'kill -TSTP $$'; echo st:$?; kill -9 %1; echo done",
    "set -m; sh -c 'exit 5' | sh -c 'kill -TSTP $$'; echo st:$?; bg %1; wait %1; echo w:$?",
    "set -m; sh -c 'exit 5' | sh -c 'kill -TSTP $$'; echo st:$?; fg %1; echo f:$?",
    "set -m; sh -c 'kill -TSTP $$'; echo st:$?; kill -9 %1; kill -CONT %1",
    "set -m; sh -c 'kill -TSTP $$'; wait %1; echo w:$?; wait %1; echo w2:$?; kill -9 %1",
    "set -m; sh -c 'kill -TSTP $$'; wait; echo wall:$?; kill -9 %1",
    "set -m; sh -c 'kill -TSTP $$'; j=$(mktemp); jobs > \"$j\"; sed -e 's/Stopped.*/Stopped/' \"$j\"; " \
    "jobs > \"$j\"; sed -e 's/Stopped.*/Stopped/' \"$j\"; rm -f \"$j\"; kill -9 %1",
    "set -m; sh -c 'kill -TSTP $$'; kill %1; echo k:$?; j=$(mktemp); jobs > \"$j\"; " \
    "sed -e 's/Stopped.*/Stopped/' \"$j\"; rm -f \"$j\"; kill -9 %1",
    "set -m; sh -c 'kill -TSTP $$'; kill -9 %1; kill -CONT %1; sleep 0.2; wait %1; echo w:$?",
    "set -m; sh -c 'kill -TSTP $$'; exit 3",
    "set -m; sh -c 'kill -TSTP $$'; exit 3; exit 4",
    "set -m; sh -c 'kill -TSTP $$'; exit 3; echo mid:$?; exit 4"
  ].freeze

  describe 'stopped jobs' do
    stopped.each.with_index(1) do |snippet, index|
      id = format('jc-stop-%03d', index)

      it "#{id}: matches dash under Timeout for: #{snippet}" do
        Timeout.timeout(10) { expect(rush_in_session(snippet)).to eq(dash_in_session(snippet)) }
      end
    end
  end

  # fg and bg (rush-mv8.5), off-tty: SIGCONT + wait need no terminal, so the
  # whole resume choreography is corpus-pinnable — fg's stdout goes to
  # /dev/null (dash prints the command text; rush's column arrives with
  # rush-mv8.6). The per-job job-control bit outlives set +m and never
  # appears retroactively (probed).
  resume = [
    "set -m; sh -c 'kill -TSTP $$'; fg %1 >/dev/null; echo st:$?; " \
    'j=$(mktemp); jobs > "$j"; wc -l < "$j"; rm -f "$j"',
    "set -m; sh -c 'kill -TSTP $$; exit 7'; fg %1 >/dev/null; echo st:$?",
    "set -m; sh -c 'kill -TSTP $$'; fg >/dev/null; echo st:$?",
    "set -m; sh -c 'kill -TSTP $$; echo resumed'; bg %1 >/dev/null; wait %1; echo w:$?",
    'set -m; sleep 0.2 & fg %1 >/dev/null; echo st:$?',
    'set -m; sleep 0.2 & bg %1 >/dev/null; echo b:$?; wait %1; echo w:$?',
    "set -m; sh -c 'kill -TSTP $$'; set +m; fg %1 >/dev/null; echo st:$?",
    'sleep 0.2 & set -m; fg %1 >/dev/null; echo st:$?; wait %1',
    "set -m; sh -c 'kill -TSTP $$; kill -TSTP $$'; fg %1 >/dev/null; echo st:$?; " \
    'j=$(mktemp); jobs > "$j"; sed -e "s/Stopped.*/Stopped/" "$j"; rm -f "$j"; kill -9 %1; kill -CONT %1',
    "set -m; sh -c 'kill -TSTP $$; exit 3'; sh -c 'kill -TSTP $$; exit 5'; fg %1 %2 >/dev/null; echo st:$?",
    "set -m; sh -c 'kill -TSTP $$'; kill -9 %1; kill -CONT %1; sleep 0.2; wait %1 >/dev/null; " \
    'fg %1 >/dev/null; echo st:$?',
    'set -m; fg >/dev/null; echo st:$?',
    "set -m; sh -c 'kill -TSTP $$'; bg %9 >/dev/null; echo b:$?; kill -9 %1; kill -CONT %1"
  ].freeze

  describe 'fg and bg' do
    resume.each.with_index(1) do |snippet, index|
      id = format('jc-fgbg-%03d', index)

      it "#{id}: matches dash under Timeout for: #{snippet}" do
        Timeout.timeout(10) { expect(rush(snippet)).to eq(dash(snippet)) }
      end
    end
  end

  # The jobs command-text column (rush-mv8.6): dash keeps text for jobctl
  # jobs on and off a tty, rendered canonically from the AST — each line
  # below pins rush's CommandText against the live oracle, byte for byte.
  # (Origin-of-quoting nuances dash preserves through its lexer — e.g.
  # dquote-escaped \$ printing unescaped — stay out; the journal records
  # them.)
  describe 'the jobs command-text column' do
    rendered = [
      'sleep 5',
      "sh -c 'kill -TSTP $$' ss",
      'sleep $T',
      'sleep "$T" x',
      'sleep ${T:-9}',
      'sleep "$@" "$?"',
      'sleep $(echo 9)',
      'sleep $((1+2))',
      "sleep 'a b'",
      'sleep 9 >/dev/null 2>&1',
      'X=1 sleep 9',
      'if true; then sleep 9; fi',
      'while true; do sleep 1; done',
      'for i in 1 2; do sleep 3; done',
      'for i; do sleep 3; done',
      'case a in a|b) sleep 9;; esac',
      'sleep 9 && echo never',
      '! sleep 9',
      '(sleep 9)',
      '{ sleep 9; echo x; }'
    ].freeze

    rendered.each.with_index(1) do |command, index|
      id = format('jc-text-%03d', index)

      it "#{id}: matches dash under Timeout for: #{command}" do
        snippet = "set -m; #{command} & jobs; kill -9 %1 2>/dev/null; kill -CONT %1 2>/dev/null; wait"
        Timeout.timeout(10) { expect(rush(snippet)).to eq(dash(snippet)) }
      end
    end
  end

  # fg/bg echo their job's text now, and the jobs listing carries it — the
  # /dev/null projections above predate the column and stay as regression
  # cover for the bare choreography.
  describe 'fg, bg and jobs with the text column' do
    text_resume = [
      "set -m; sh -c 'kill -TSTP $$' zz; fg %1; echo st:$?",
      "set -m; sh -c 'kill -TSTP $$' zz; bg %1; wait %1; echo w:$?",
      "set -m; sh -c 'kill -TSTP $$' zz; j=$(mktemp); jobs > \"$j\"; cat \"$j\"; rm -f \"$j\"; " \
      'kill -9 %1; kill -CONT %1'
    ].freeze

    text_resume.each.with_index(1) do |snippet, index|
      id = format('jc-text-fgbg-%03d', index)

      it "#{id}: matches dash under Timeout for: #{snippet}" do
        Timeout.timeout(10) { expect(rush(snippet)).to eq(dash(snippet)) }
      end
    end
  end
end
