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
    # subshells: a live job is not the subshell's child (status 0, as dash),
    # an unknown pid stays 127, and a status the parent already reaped during
    # a foreground wait is inherited as remembered. (The dead-but-unreaped
    # shape `exit 7 & (wait $!)` is inherently racy in dash — whether its
    # pre-fork poll caught the zombie decides 7 vs 0 — so it stays out.)
    'sleep 0.3 & (wait $!; echo sub=$?)',
    '(wait 99999; echo sub=$?)',
    'false & sleep 0.3; (wait $!; echo sub=$?)',
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
end
