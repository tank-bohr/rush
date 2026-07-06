# frozen_string_literal: true

# Trap and signal-handling differential cases.
RSpec.describe 'rush vs dash (differential traps/signals corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

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
end
