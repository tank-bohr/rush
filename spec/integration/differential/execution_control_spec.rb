# frozen_string_literal: true

# Command substitution statuses, compound redirects, loop control, return/exit,
# shift, hash, and incremental execution cases.
RSpec.describe 'rush vs dash (differential execution/control corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  corpus = [
    # backtick command substitution is active inside double quotes
    'echo "X`echo hi`Y"',
    'echo "a `echo b c` d"',
    'v="`echo a` `echo b`"; echo "$v"',
    'echo "nested `echo X`Y`echo Z`"',
    'echo "lit \`not sub\` done"',
    # redirects on compound commands (output diverted to /dev/null is flush-safe,
    # unlike reading a just-written file back within the same shell)
    '{ echo hidden; } > /dev/null; echo shown',
    'if true; then echo x; fi > /dev/null; echo done',
    '{ echo keep; } 2>/dev/null',
    'for i in 1 2; do echo $i; done > /dev/null; echo end',
    '(echo sub) > /dev/null; echo o',
    'case x in x) echo m;; esac >/dev/null; echo c',
    'case x in x) for i in a b; do echo $i; done;; esac',
    'case x in x) case y in y) echo nested;; esac;; esac',
    'case x in x) if true; then echo yes; fi;; esac',
    'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done >/dev/null; echo w',
    'until false; do echo loop; break; done >/dev/null; echo u',
    '{ false; } >/dev/null; echo $?',
    'if true; then echo y; else echo n; fi 2>/dev/null',
    # a no-command-word command takes the last command substitution's status;
    # with no substitution it is 0 (resets even after a prior failure), and a
    # later $? in the same command still sees the previous command's status
    'true; x=$(false); echo $?',
    'false; x=$(true); echo $?',
    'false; x=foo; echo $?',
    'x=$(true)$(false); echo $?',
    'x=$(false)$(true); echo $?',
    'a=$(true) b=$(false); echo $?',
    'true; $(false); echo $?',
    'false; $(:); echo $?',
    'true; x=$(exit 5); echo $?',
    'x=$(true; false); echo $?',
    'x=$(false) true; echo $?',
    'false; echo "$(true)-$?"',
    'y=$(x=$(false)); echo $?',
    'export x=$(false); echo $?',
    'x=pre$(false)post; echo $?',
    'set -e; x=$(false); echo unreached',
    'set -e; x=$(true); echo reached',
    'set -e; if x=$(false); then echo t; else echo e; fi',
    'set -e; x=$(true) y=$(false); echo unreached',
    'set -e; v=$(false) || echo recovered; echo after',
    # bare `set -o` prints the settings table and bare `set +o` the re-input
    # form (POSIX XCU set); rows for options both shells share compare
    # byte-exact, and the +o round-trip restores flags through eval
    'set -o | grep errexit',
    'set -e; set -o | grep errexit',
    'set -m; set -o | grep monitor',
    'set +o | grep pipefail',
    'set -o pipefail; set +o | grep pipefail',
    'set -u; s=$(set +o); set +u; eval "$s"; echo "u:$-"',
    'set -o >/dev/null; set +o >/dev/null; echo rc=$?',
    # noexec starts after the set builtin succeeds and suppresses every later
    # command, including async launch and an already-installed EXIT trap.
    'echo before; set -n; echo after; false &',
    'set -o noexec; echo after; set +n; echo still-after',
    "trap 'echo exit' 0; set -n; echo after",
    # set -x prefixes each trace line with the expanded PS4 (default '+ ';
    # parameter expansion happens per trace line, so $? reflects the moment
    # of tracing). Trace goes to stderr — outside the [stdout,exitstatus]
    # model — so exec 2>&1 routes it into the comparison.
    'exec 2>&1; set -x; echo hi',
    'PS4="[trace] "; exec 2>&1; set -x; echo hi',
    'X=Y; PS4="[$X] "; exec 2>&1; set -x; echo hi',
    'V=zz; PS4="${V}> "; exec 2>&1; set -x; echo hi',
    'PS4=; exec 2>&1; set -x; echo hi',
    'PS4="[$?] "; exec 2>&1; false; set -x; echo hi',
    # pipefail changes a pipeline's status from the last stage to the rightmost
    # non-zero stage; all-zero pipelines stay successful, +o disables it, and !
    # negates the pipefail-adjusted status.
    'false | true; echo $?',
    'set -o pipefail; false | true; echo $?',
    'set -o pipefail; true | false; echo $?',
    'set -o pipefail; (exit 3) | (exit 7) | true; echo $?',
    'set -o pipefail; true | true; echo $?',
    'set -o pipefail; set +o pipefail; false | true; echo $?',
    'set -o pipefail; ! false | true; echo $?',
    'set -e -o pipefail; false | true; echo no',
    # break and continue are successful builtins: they leave $? at 0, both after
    # the loop and (for continue) in the next iteration's body. A loop that exits
    # normally still reports its last body status.
    'for i in 1; do false; break; done; echo $?',
    'for i in 1 2; do false; continue; done; echo $?',
    'for i in 1 2; do echo "rc=$?"; false; continue; done; echo end=$?',
    'while true; do false; break; done; echo $?',
    'until false; do false; break; done; echo $?',
    'for i in 1; do for j in 1; do false; break 2; done; done; echo $?',
    'i=0; while [ $i -lt 2 ]; do i=$((i+1)); false; continue; done; echo $?',
    'for i in 1 2; do false; done; echo $?',
    # break/continue are lexically scoped to loops in the same execution
    # environment: a stray one with no enclosing loop is a no-op (execution
    # continues), a level past the nesting is clamped, and one inside a function
    # cannot reach the caller's loop. eval/dot/group bodies run inline and keep
    # the count, so break in them still exits the surrounding loop.
    'break; echo after',
    'continue; echo after',
    'echo a; break; echo b',
    'if true; then break; fi; echo after',
    '{ break; echo in; }; echo out',
    '( break; echo in ); echo out',
    'f() { break; echo in; }; f; echo out',
    'f() { break; echo in; }; for i in 1; do f; echo loop; done; echo out',
    'f() { continue; }; for i in 1 2; do f; echo l$i; done; echo done',
    'for i in 1; do for j in 1; do break 5; done; echo inner; done; echo $?',
    'for i in 1 2; do for j in a; do continue 2; done; echo inner; done; echo done',
    'for i in 1 2 3; do for j in a b; do echo $i$j; continue 2; done; done',
    "for i in 1 2 3; do eval 'break'; echo no; done; echo done",
    # break/continue validate their level operand (a positive integer) even with
    # no enclosing loop: a non-numeric, zero or out-of-range value is a
    # special-builtin error that aborts a non-interactive shell with 2.
    'break abc; echo after',
    'for i in 1; do break 0; done; echo after',
    'for i in 1; do continue xy; done; echo after',
    'for i in 1; do break -1; done; echo after',
    "trap 'echo bye' EXIT; continue abc",
    'for i in 1 2; do for j in a; do break +2; done; echo in; done; echo $?',
    # a return not caught by a function or dot script acts like exit with that
    # code (non-interactive): at the top level it exits the shell (firing the
    # EXIT trap), in a subshell or command substitution it ends only that.
    'return 3; echo after',
    'echo a; return 5; echo b',
    'x=5; return $x; echo after',
    'for i in 1 2; do return 9; done; echo after',
    '{ return 3; }; echo after',
    'if true; then return 4; fi; echo after',
    "eval 'return 3'; echo after",
    'false; return; echo after',
    "trap 'echo bye' EXIT; return 3",
    "trap 'echo rc=$?' EXIT; false; return",
    '( return 3 ); echo sub=$?',
    'x=$(return 5); echo $?',
    'echo "[$(return 5; echo body)]"',
    'f() { return 3; }; f; echo after=$?',
    # exit/return reject an invalid numeric operand (empty, negative, non-decimal)
    # as a special-builtin error: a non-interactive shell aborts with status 2,
    # firing the EXIT trap; a valid operand (codes <=255 here) is accepted.
    'return abc; echo after',
    'f() { return abc; echo in; }; f; echo after=$?',
    'exit xy; echo after',
    'echo a; exit 1z; echo b',
    'f() { return -1; }; f; echo a=$?',
    'exit 0x10',
    "trap 'echo bye' EXIT; return abc",
    '( exit abc ); echo sub=$?',
    'f() { return +5; }; f; echo a=$?',
    'f() { return 007; }; f; echo a=$?',
    'exit 1 2; echo after',
    # a valid exit code wider than a byte stays wide in $? (in-process); it wraps
    # to 0-255 only at a real process boundary (the shell's own exit, a subshell).
    'f() { return 300; }; f; echo $?',
    'g() { return 1000; }; g; echo "rc=$?"; true; echo $?',
    'f() { return 256; }; f; echo $?',
    'exit 300',
    '( exit 300 ); echo $?',
    'set -e; f() { return 300; }; f; echo no',
    # shift is a special builtin: shifting more than $# ("can't shift that many")
    # and a bad operand ("Illegal number") both abort a non-interactive shell with
    # 2 (firing the EXIT trap). A valid count <= $# succeeds; extra operands and a
    # leading +/zeros/blanks are accepted like dash's number(); 0 is a no-op.
    'shift; echo after',
    'set a b; shift 5; echo after',
    'set a b c; shift 3; echo "[$*]$?"',
    'set a b c; shift 0; echo "[$*]"',
    'set a; shift; shift; echo after',
    'trap "echo bye" EXIT; shift',
    'shift abc; echo after',
    'shift -1; echo after',
    'set a b c; shift +1; echo "[$*]"',
    'set a b c; shift 1 2; echo "[$*]"',
    'set a b c; shift 1abc; echo after',
    '( shift ); echo sub=$?',
    'umask; umask -S',
    'umask 077; umask; umask u=rwx,g=rx,o=rx; umask',
    'umask go=; umask; echo rc=$?',
    'umask 022; umask +w; umask',
    'umask 066; umask u=r; umask',
    'umask 277; umask uua+w; umask',
    'ulimit; ulimit -f; ulimit -n; ulimit -Hn',
    'ulimit -a',
    'ulimit -Sn 64; echo "n=$(ulimit -Sn):$(ulimit -Hn)"',
    'ulimit -f 2; echo "f=$(ulimit -f)"',
    # hash is a regular builtin: an empty cache lists nothing, -r clears, a builtin
    # name and a slash path are no-ops, an unknown name errors (status 1) but does
    # not abort. (PATH-resolving cases need a controlled PATH; covered separately.)
    'hash', 'hash -r', 'hash echo; hash', 'hash -r; hash',
    'hash nosuchcmd_rush_zzz; echo $?', 'hash /no/such/path; hash; echo done',
    # incremental execution: complete commands run (and flush) before a later
    # syntax error aborts the rest; blank/comment lines preserve $?; a fatal error
    # fires the EXIT trap with $?=2 (which may override the exit code via exit)
    "echo one\nbad )\necho two",
    'echo a; bad )',
    "false\n\necho $?",
    "false\n# a comment\necho $?",
    "greet() { echo \"hi $1\"; }\ngreet world",
    "x=1\necho $x\nx=2\necho $x",
    "set -e\nfalse\necho nope",
    "cat <<EOF\nbody line",
    "trap 'echo bye' EXIT\necho one\nbad )",
    "trap 'echo rc=$?' EXIT\ntrue\nbad )",
    "trap 'echo bye' EXIT\nreadonly x=1\nx=2\necho after",
    "trap 'echo rc=$?' EXIT\nset -u\necho \"$missing\"\necho after",
    "trap 'exit 9' EXIT\necho one\nbad )",
    # a pipeline stage is a subshell environment (POSIX 2.12): exit/return end
    # only the stage (a real process boundary truncates to 0-255), loop control
    # is inert, an EXIT trap set inside fires with the stage's io, and a fatal
    # error aborts just that stage with status 2
    'exit 4 | exit 6; echo $?',
    'true | exit 5; echo $?',
    'exit 5 | true; echo $?',
    'true | exit 300; echo $?',
    'true | return 7; echo $?',
    'f() { return 3; }; true | f; echo $?',
    'while true; do break | true; echo once; break; done; echo out',
    'i=0; while [ $i -lt 2 ]; do i=$((i+1)); true | continue; echo body; done; echo done',
    'true | { trap "echo bye" EXIT; true; }; echo $?',
    '{ trap "echo bye" EXIT; true; } | cat; echo $?',
    'readonly x=1; true | { x=2; echo unreached; }; echo $?'
  ].freeze

  corpus.each.with_index(1) do |snippet, index|
    id = format('control-%03d', index)

    it "#{id}: matches dash for: #{snippet}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end
end
