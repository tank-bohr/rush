# frozen_string_literal: true

# The terminal-free half of the job table (rush-rg2): jobs listing rendered
# byte-exactly (state column padded to 33, the command column empty away from
# a tty, as dash keeps no command text there), numbering that reuses the
# lowest freed slot, Done entries freed once displayed (-p does not free),
# %job ids in wait and kill, and fg/bg refusing without terminal job control.
# kill %job targets the job's process group — which does not exist without
# set -m, so delivery fails status 1 and the job survives, exactly like dash.
RSpec.describe 'rush vs dash (differential jobs corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  corpus = [
    # listing: order, marks, states, padding
    'jobs; echo st=$?',
    'sleep 0.3 & sleep 0.4 & jobs',
    'sleep 0.3 & sleep 0.35 & sleep 0.4 & jobs',
    'exit 0 & sleep 0.1; jobs',
    'exit 5 & sleep 0.1; jobs; echo ---; jobs',
    'sleep 5 & kill -9 $!; sleep 0.1; jobs',
    'sleep 5 & kill $!; sleep 0.1; jobs',
    'for i in 1 2 3 4 5 6 7 8 9; do sleep 0.3 & done; sleep 0.35 & jobs',
    # freeing each displayed finished entry re-promotes the next to current
    # before it prints, so mixed listings shift their + marks like dash's
    'exit 0 & exit 5 & sleep 5 & kill -9 $!; sleep 0.1; jobs',
    'sleep 0.3 & exit 5 & sleep 0.1; jobs',
    'exit 5 & sleep 0.3 & sleep 0.1; jobs',
    # a forked child still LISTS the inherited table — the subshell
    # environment duplicates the async-pid knowledge (POSIX 2.12; rush-r6i)
    # — while the entries stay unwaitable there; dash reaches the same
    # listing through its unforked single-builtin pipeline stage
    'sleep 0.3 & jobs | cat; echo done',
    'set -m; sleep 0.3 & jobs | cat; kill -9 %1; echo done',
    'sleep 0.3 & jobs -p | wc -l; echo done',
    # numbering reuses the lowest freed slot; an emptied table starts at [1]
    'sleep 0.3 & exit 0 & sleep 0.1; jobs >/dev/null; sleep 0.4 & jobs',
    'exit 0 & sleep 0.1; jobs >/dev/null; sleep 0.2 & jobs',
    # displaying a finished job frees it (plain and -l); -p does not
    'false & sleep 0.1; jobs >/dev/null; wait $!; echo st=$?',
    'false & sleep 0.1; jobs >/dev/null; wait %1; echo st=$?',
    'exit 5 & sleep 0.1; jobs -l >/dev/null; wait $!; echo st=$?',
    'exit 5 & sleep 0.1; jobs -p >/dev/null; wait $!; echo st=$?',
    'sleep 5 & kill -9 $!; sleep 0.1; jobs; wait %1; echo st=$?',
    # %ids in wait: current/previous/numbered, repeats remembered, misses
    'exit 3 & wait %1; echo st=$?',
    'exit 3 & exit 4 & sleep 0.1; wait %%; echo a=$?; wait %+; echo b=$?; wait %-; echo c=$?',
    'exit 3 & sleep 0.1; wait %; echo st=$?',
    'false & sleep 0.1; wait %1; echo a=$?; wait %1; echo b=$?',
    'wait %; echo st=$?',
    'sleep 0.2 & wait %-; echo st=$?',
    'sleep 0.1 & wait %2; echo st=$?',
    'sleep 0.2 & wait %sle; echo st=$?',
    # %ids in kill: group target fails without job control, misses are 2
    'sleep 0.2 & kill %1; echo k=$?; wait $!; echo w=$?',
    'sleep 0.2 & kill %; echo st=$?',
    'sleep 0.1 & kill %2; echo st=$?',
    # jobs with operands renders up to the first unknown %id
    'sleep 0.2 & jobs %1',
    'sleep 0.2 & sleep 0.25 & jobs %1 %9 %2; echo st=$?',
    # fg and bg refuse without terminal job control
    'fg; echo st=$?',
    'bg; echo st=$?',
    'sleep 0.2 & fg; echo st=$?',
    'sleep 0.2 & fg %1; echo st=$?',
    'sleep 0.2 & bg %1; echo st=$?',
    # the three are known builtins
    'type jobs; command -v fg; command -v bg'
  ].freeze

  corpus.each.with_index(1) do |snippet, index|
    id = format('jobs-%03d', index)

    it "#{id}: matches dash for: #{snippet}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end
end
