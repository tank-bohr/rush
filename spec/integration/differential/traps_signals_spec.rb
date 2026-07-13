# frozen_string_literal: true

require 'shellwords'

# Trap and signal-handling differential cases.
RSpec.describe 'rush vs dash (differential traps/signals corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  def with_fifo
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'gate')
      system('mkfifo', path)
      yield(path)
    end
  end

  corpus = [
    # trap: only stdout + exit status are compared, so the "bad trap" diagnostics
    # and the not-found noise from a bare action at EXIT (both on stderr) are moot.
    "trap 'echo bye' EXIT; echo body",
    "trap 'echo bye' EXIT; echo body; exit 4",
    "trap 'echo rc=$?' EXIT; false",
    "trap 'echo t; exit 9' EXIT; exit 2",
    # a bare `exit` in the EXIT trap exits with the shell's terminating status,
    # not the trap body's last $?.
    "trap 'echo T; exit' EXIT; (exit 3)",
    "trap ':; exit' EXIT; false",
    "false; trap 'echo s=$?; :; exit' EXIT; return 1",
    "f() { (exit 0); exit 42; }; trap 'echo T; exit' EXIT; f",
    "trap 'false; exit' EXIT; exit 127",
    "trap 'echo c' EXIT; if true; then exit 7; fi",
    "trap 'echo X; shift' EXIT",
    %q[trap '(trap "echo inner-sub" EXIT; :)' EXIT],
    %q[trap 'x=$(trap "echo inner-cs" EXIT; :); echo "[$x]"' EXIT],
    "trap 'echo T' USR1; sh -c 'kill -USR1 $1; echo S' sh $$; echo A",
    "trap 'echo in=$?' USR1; sh -c 'kill -USR1 $1; exit 5' sh $$; echo out=$?",
    "trap 'echo U1' USR1; trap 'echo U2' USR2; sh -c 'kill -USR2 $1; kill -USR1 $1' sh $$",
    "trap 'echo A; kill -USR2 $$; echo B' USR1; trap 'echo C' USR2; kill -USR1 $$; echo D",
    "n=0; trap 'n=$((n+1)); echo A$n; if [ $n -eq 1 ]; then kill -USR1 $$; fi; echo B$n' USR1; " \
    'kill -USR1 $$; echo D',
    "trap 'echo T' USR1; trap 'echo E' EXIT; sh -c 'kill -USR1 $1; echo S' sh $$",
    "trap 'echo T' USR1; trap 'echo E1; kill -USR1 $$; echo E2' EXIT",
    "trap 'echo a' EXIT; trap 'echo b' INT; trap; echo end",
    "trap 'echo hi' INT TERM HUP; trap",
    "trap '' INT; trap",
    "trap 'echo e' EXIT; trap - EXIT; echo body",
    "trap 'echo e' EXIT; trap EXIT; echo body",
    "trap '' INT TERM; trap - INT; trap",
    "trap 'x' int Term hUp; trap",
    "trap 'echo z' 0; trap",
    'trap x sigterm 2>/dev/null; echo rc=$?',
    'trap x 99 2>/dev/null; echo rc=$?',
    'trap x INT BADD TERM 2>/dev/null; trap',
    'trap',
    "x=5; trap 'echo $x' EXIT; x=9",
    "trap 'echo done' EXIT; for i in 1 2 3; do echo $i; done",
    "f() { trap 'echo ft' EXIT; }; f; echo after",
    # kill: -0 probes existence; a self-directed signal terminates rush exactly
    # as it does dash (Open3 reports a signalled exit as a nil status for both).
    'kill -0 $$; echo rc=$?',
    'kill -0 999999 2>/dev/null; echo rc=$?',
    'kill -s 0 $$; echo rc=$?',
    'kill -l 15',
    'kill -l 9',
    'kill -l 143',
    'kill -l 130',
    'kill -l 99 2>/dev/null; echo rc=$?',
    'kill -l 0 2>/dev/null; echo rc=$?',
    'kill -BADD $$ 2>/dev/null; echo rc=$?',
    'kill 2>/dev/null; echo rc=$?',
    'kill -TERM $$; echo after',
    'kill -15 $$; echo after',
    'type kill',
    # trap + kill: a delivered signal runs the action, then execution continues;
    # ignore swallows it, reset restores the default (which terminates).
    "trap 'echo caught' TERM; kill -TERM $$; echo after",
    "trap '' TERM; kill -TERM $$; echo after",
    "trap 'echo caught; exit 5' TERM; kill -TERM $$; echo after",
    "true; trap 'false' TERM; kill -TERM $$; echo $?",
    "trap 'echo x' TERM; trap - TERM; kill -TERM $$; echo after",
    "trap 'echo gotint' INT; kill -INT $$; echo after",
    "trap 'echo bye' EXIT; trap 'echo caught' TERM; kill -TERM $$; echo after",
    "n=0; trap 'n=1' TERM; kill -TERM $$; echo n=$n"
  ].freeze

  corpus.each.with_index(1) do |snippet, index|
    id = format('signals-%03d', index)

    it "#{id}: matches dash for: #{snippet}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end

  describe 'traps interrupting wait and read' do
    it 'interrupts wait with 128+signal and leaves the job waitable' do
      with_fifo do |gate|
        source = "f=#{Shellwords.escape(gate)}; trap 'echo T:$?; echo go > \"$f\"' USR1; " \
                 "sh -c 'while :; do case $(ps -o stat= -p \"$1\") in S*) break;; esac; done; " \
                 "kill -USR1 \"$1\"; read x < \"$2\"; exit 7' sh $$ \"$f\" & p=$!; " \
                 'wait $p; echo W:$?; wait $p; echo W2:$?'
        expect(rush(source)).to eq(dash(source))
      end
    end

    it 'interrupts read with 1, assigning only bytes consumed before the signal' do
      with_fifo do |gate|
        source = "f=#{Shellwords.escape(gate)}; exec 3<>\"$f\"; printf part >&3; " \
                 "trap 'echo T:$?; echo data >&3' USR1; " \
                 "sh -c 'while :; do case $(ps -o stat= -p \"$1\") in S*) break;; esac; done; " \
                 "kill -USR1 \"$1\"' sh $$ & p=$!; read x <&3; echo R:$?:\"$x\"; " \
                 'read y <&3; echo R2:$?:"$y"; wait $p'
        expect(rush(source)).to eq(dash(source))
      end
    end
  end

  # printsignal (rush-hkp): a signal-killed foreground job reports strsignal
  # on the stderr in effect at the wait, INT/PIPE excluded, wait-by-pid
  # reporting and bare wait silent. Redirecting that stderr into a file and
  # cat-ing it back makes the report corpus-visible despite the
  # stdout-only comparison; both %s in each template take the temp path.
  printsignal = [
    "sh -c 'kill -TERM $$' 2>%s; echo rc=$?; cat %s",
    "sh -c 'kill -USR1 $$' 2>%s; echo rc=$?; cat %s",
    "sh -c 'kill -SEGV $$' 2>%s; echo rc=$?; cat %s",
    "sh -c 'kill -INT $$' 2>%s; echo rc=$?; cat %s",
    "{ sh -c 'kill -KILL $$' | cat; } 2>%s; echo rc=$?; cat %s",
    "{ x=$(sh -c 'kill -KILL $$'); } 2>%s; echo rc=$?; cat %s",
    '{ sleep 2 & kill -KILL $!; wait $!; } 2>%s; echo rc=$?; cat %s',
    '{ sleep 2 & kill -KILL $!; wait; } 2>%s; echo rc=$?; cat %s'
  ].freeze

  printsignal.each.with_index(1) do |template, index|
    id = format('printsignal-%03d', index)

    it "#{id}: matches dash for: #{template}" do
      Tempfile.create('rush_printsignal') do |file|
        snippet = format(template, file.path, file.path)
        expect(rush(snippet)).to eq(dash(snippet))
      end
    end
  end
end
