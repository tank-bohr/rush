# frozen_string_literal: true

# The wait builtin and background-job reaping: launch/exit statuses,
# remembered statuses, unknown pids, malformed operands, and what a subshell
# inherits. Where dash diverges from POSIX (`wait known unknown` keeps the
# known status; the standard gives the unknown last operand its 127) the
# standard wins — pinned in the builtin's unit specs, kept out of this corpus.
RSpec.describe 'rush vs dash (differential background/wait corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  corpus = [
    # bare invocations and operand validation (diagnostics land on ignored
    # stderr; the statuses are the contract)
    'wait; echo $?',
    'wait 99999; echo $?',
    'wait 0; echo $?',
    'wait +5; echo $?',
    'wait -- 99999; echo $?',
    'wait abc; echo $?',
    'wait -; echo $?',
    'wait -5; echo $?',
    'wait 99999999999999; echo $?',
    # background jobs: launch status, exit statuses, remembered repeats
    'exit 7 & wait $!; echo $?',
    'false & wait $!; echo a=$?; wait $!; echo b=$?',
    'exit 3 & wait; echo $?',
    'true & exit 3 & wait; echo $?',
    'exit 3 & p1=$!; exit 5 & p2=$!; wait $p1 $p2; echo $?',
    'exit 3 & wait 99999 $!; echo $?',
    'exit 3 & wait $!; wait; echo $?',
    'true | false & wait $!; echo $?',
    'exit 4 | exit 6 & wait $!; echo $?',
    'sleep 5 & p=$!; kill -9 $p; wait $p; echo $?',
    # async isolation (POSIX 2.9.3.1 / 2.11, job control disabled): the child
    # starts with SIGINT/SIGQUIT ignored — a real SIG_IGN that survives exec
    # and nested subshells, which `trap` overrides and `trap - INT` resets to
    # the OS default — while TERM still kills. The settle sleep matters: dash
    # has the same fork race, and an instant kill beats the child's SIG_IGN
    # setup in both shells.
    'sleep 0.4 & sleep 0.1; kill -INT $!; wait $!; echo st=$?',
    'sleep 0.4 & sleep 0.1; kill -QUIT $!; wait $!; echo st=$?',
    '( sleep 0.4 ) & sleep 0.1; kill -INT $!; wait $!; echo st=$?',
    '{ trap "echo got" INT; sleep 0.4; } & sleep 0.1; kill -INT $!; wait $!; echo st=$?',
    '{ trap - INT; sleep 0.4; } & sleep 0.1; kill -INT $!; wait $!; echo st=$?',
    'sleep 0.4 & sleep 0.1; kill $!; wait $!; echo st=$?',
    # async stdin is /dev/null unless the list redirects it itself
    "cat <<E & wait $!\nhd\nE\necho st=$?",
    # forked child environments start with no jobs of their own (POSIX 2.12):
    # wait by pid reports 127 in a real subshell, a pipeline stage, an async
    # child and a command substitution alike. Tail-position `( )` forms stay
    # out of the corpus: dash's EV_EXIT optimization runs those in the main
    # shell without forking, so its waits succeed where a true subshell
    # reports 127 (bash agrees with 127; the standard's subshell semantics
    # win — journal).
    'sleep 0.3 & (wait $!; echo sub=$?); echo tail',
    'exit 7 & (wait $!; echo sub=$?); echo tail',
    'false & sleep 0.3; (wait $!; echo sub=$?); echo tail',
    '(wait 99999; echo sub=$?)',
    'sleep 0.2 & true | { wait $!; echo st=$?; }',
    'sleep 0.3 & { wait $!; echo inner=$?; } & wait; echo tail',
    'false & sleep 0.1; echo "x$(wait $!; echo =$?)"; echo tail',
    # wait is a known regular builtin
    'command -v wait',
    'type wait'
  ].freeze

  corpus.each.with_index(1) do |snippet, index|
    id = format('wait-%03d', index)

    it "#{id}: matches dash for: #{snippet}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end

  it 'wait-inp: async stdin is /dev/null, not the pipe feeding the shell' do
    snippet = 'cat & wait $!; echo st=$?'
    expect(rush(snippet, "hi\n")).to eq(dash(snippet, "hi\n"))
  end
end
