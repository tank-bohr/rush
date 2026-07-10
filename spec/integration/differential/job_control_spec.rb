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

  tstp.each.with_index(1) do |snippet, index|
    id = format('jc-tstp-%03d', index)

    it "#{id}: matches dash under Timeout for: #{snippet}" do
      Timeout.timeout(10) { expect(rush(snippet)).to eq(dash(snippet)) }
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
end
