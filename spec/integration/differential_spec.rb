# frozen_string_literal: true

require 'open3'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

# Differential tests: each snippet must produce the same stdout and exit status
# under rush as under dash, the reference implementation we verify against. The
# authority is the POSIX standard — where dash is known to diverge from it, rush
# follows the standard and that case is left out here. Skipped when dash is
# unavailable. These run the real exe/rush in a child process, so they do not
# contribute to SimpleCov; the in-process unit specs own coverage.
RSpec.describe 'rush vs dash (differential)' do
  def project_root = File.expand_path('../..', __dir__)

  def rush(source, input = nil)
    out, _err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rush', '-c', source,
                                       chdir: project_root, stdin_data: input.to_s)
    [out, status.exitstatus]
  end

  def dash(source, input = nil)
    out, _err, status = Open3.capture3('dash', '-c', source, stdin_data: input.to_s)
    [out, status.exitstatus]
  end

  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  corpus = [
    '[ -n x ] && echo y',
    '[ -z "" ] && echo y',
    '[ -z nonempty ]; echo $?',
    'test abc = abc && echo eq',
    'test abc = abd || echo ne',
    '[ 3 -lt 10 ] && echo lt',
    '[ 10 -ge 10 ] && echo ge',
    '[ 10 -ne 10 ]; echo $?',
    'if [ ! -n "" ]; then echo blank; fi',
    'test ! abc = abc; echo $?',
    '[ "(" = "(" ] && echo paren',
    '[ \( -n x \) ] && echo group',
    'x=5; [ "$x" -eq 5 ] && echo five',
    'test; echo $?',
    'test a b c; echo $?',
    '[ -d / ] && echo y',
    '[ -e /dev/null ] && echo y',
    '[ -f /dev/null ]; echo $?',
    '[ -r /dev/null ] && echo y',
    '[ -s /dev/null ]; echo $?',
    '[ -f /no/such/rush_xyz ]; echo $?',
    'set a b c; echo "$1 $2 $3 $#"',
    'set a b c; shift; echo "$1 $#"',
    'set a b c; shift 2; echo "$1 $#"',
    'set -- x y; echo "$# $1 $2"',
    'set --; echo "[$#]"',
    'set a b c; shift 0; echo $#',
    'set a b c; for x in "$@"; do echo "[$x]"; done',
    'set "a b" c; for x in "$@"; do echo "[$x]"; done',
    'set --; for x in "$@"; do echo no; done; echo done',
    'set a b c; for x in $@; do echo "[$x]"; done',
    'set a b c; echo "$*"',
    'set a b c; echo "pre$@post"',
    'set one; echo "x$@y"',
    'set --; echo "z$@w"',
    'export X=hi; printenv X',
    'X=local; printenv X; echo "rc=$?"',
    'export X=hi; unset X; printenv X; echo "rc=$?"',
    'eval echo one two',
    'eval "echo hi; x=1"; echo $x',
    'x=5; eval "echo \$x"',
    'eval "for i in 1 2 3; do echo \$i; done"',
    'eval exit 3; echo after',
    '(echo a; echo b)',
    '(exit 3); echo $?',
    '(false); echo $?',
    'x=1; (x=2; echo "$x"); echo "$x"',
    'x=1; (unset x); echo "[$x]"',
    '(if true; then echo yes; fi)',
    'printf "%s\n" hello',
    'printf "%s=%s\n" a 1 b 2',
    'printf "%s\n" a b c',
    'printf "[%5s][%-5s]\n" hi hi',
    'printf "%03d %d %x %X %o\n" 7 42 255 255 8',
    'printf "%c%c\n" abc xyz',
    'printf "a\tb\nc\n"',
    'printf "%d\n" abc; echo "rc=$?"',
    'printf "no newline"',
    'printf "%d-%s\n" 5',
    "cat <<EOF\nplain line one\nplain line two\nEOF",
    "cat <<-END\n\t\ttabbed body\n\tEND",
    "cat <<'Q'\nliteral $x and `cmd` stay\nQ",
    "wc -l <<EOF\na\nb\nc\nEOF",
    "v=42; cat <<EOF\nvalue is $v\nEOF",
    "cat <<EOF\nsub: $(echo deep)\nEOF",
    "x=1; cat <<EOF\nescaped \\$x literal\nEOF",
    'readonly x=1; echo "$x"',
    'readonly x=1; x=2; echo after',
    'readonly x=1; unset x; echo after',
    '(readonly x=1; x=2); echo after',
    '(echo ${X:?bad}); echo after',
    'exec echo replaced; echo after',
    'exec no-such-cmd-rush-xyz; echo after',
    'x=hello; echo ${#x}',
    'echo ${#missing}',
    'f=foo.tar.gz; echo "${f#*.}|${f##*.}|${f%.*}|${f%%.*}"',
    'p=/usr/local/bin; echo "${p##*/} ${p%/*}"',
    'x=abc; echo "${x#xyz}|${x#*}|${x##*}"',
    'set -u; x=ok; echo "$x"',
    'set -u; echo "${y:-fallback}"',
    'set -u; set a b; echo "$1$2"',
    'set -u; echo "$missing"; echo after',
    'set -u; echo "$1"; echo after',
    'set -e; false; echo after',
    'set -e; true; echo after',
    'set -e; if false; then echo no; fi; echo after',
    'set -e; false || true; echo after',
    'set -e; false && echo no; echo after',
    'set -e; true && false; echo after',
    'set -e; true && false && true; echo after',
    'set -e; ! false; echo after',
    'set -e; ! true; echo after',
    'set -e; ! { false; }; echo after',
    'set -e; if true; then false; fi; echo after',
    'set -e; if true; then false; fi || echo recovered; echo after',
    'set -e; f() { false; }; f; echo after',
    'set -e; if f() { false; }; f; then echo t; else echo no; fi',
    'set -e; for i in 1 2; do false; done; echo after',
    'set -e; while true; do false; done; echo after',
    'set -e; until false; do false; done; echo after',
    'set -e; case x in x) false;; esac; echo after',
    'set -e; case x in y) false;; esac; echo after',
    'set -e; eval false; echo after',
    'set -e; set +e; false; echo after',
    'set -e; ( false ); echo after',
    'set -e; ( false; echo no ); echo after',
    'set -e; if ( false; echo more ); then echo t; else echo f; fi',
    'set -e; if true; then ( false; echo more ); fi; echo after',
    'set -e; echo "X$(false; echo hi)Y"; echo done',
    'set -e; (exit 7); echo after',
    'IFS=:; v="a::b"; set -- $v; echo $#',
    'IFS=:; v=":a:b:"; set -- $v; printf "<%s>" "$@"; echo',
    'IFS=:; v="a:"; set -- $v; echo $#',
    'IFS=:; v="a::"; set -- $v; echo $#',
    'IFS=:; v="::"; set -- $v; echo $#',
    'IFS=:; v=":"; set -- $v; echo $#',
    'IFS=:; v=""; set -- $v; echo $#',
    'IFS=" :"; v="a  :  b"; set -- $v; printf "<%s>" "$@"; echo',
    'IFS=" :"; v=":x:"; set -- $v; printf "<%s>" "$@"; echo',
    'IFS=" :"; v="  a  "; set -- $v; printf "<%s>" "$@"; echo',
    'a="x:"; b=":y"; IFS=:; set -- $a$b; echo $#',
    'a="x"; b="y"; IFS=:; set -- $a$b; echo "$#:$1"',
    'IFS=" "; v="  hi   there  "; set -- $v; echo $#',
    'IFS=":"; v="a:b"; set -- p$v"q"; printf "<%s>" "$@"; echo',
    'IFS=" "; v="  x  "; set -- "pre"$v; printf "<%s>" "$@"; echo',
    'IFS=; set -- a b c; printf "[%s]" "$*"; echo',
    'unset IFS; set -- a b c; printf "[%s]" "$*"; echo',
    'IFS=-; set -- a b c; printf "[%s]" "$*"; echo',
    'IFS=:; set -- "a b" c; set -- $*; echo $#',
    'IFS=""; set -- a b c; set -- $*; echo $#',
    'IFS=" "; set -- "p q" r; set -- $*; echo $#',
    'IFS=:; set -- a b c; X=$*; echo "[$X]"',
    'echo $((2+3*4))',
    'echo $(((2+3)*4))',
    'echo $((17/5)) $((17%5)) $((-17/5)) $((-17%5))',
    'echo $((7 % -3)) $((-7 % 3))',
    'echo $((1<<4)) $((256>>2)) $((5&3)) $((5|2)) $((5^1)) $((~0))',
    'echo $((3<5)) $((5>3)) $((3<=3)) $((4>=9)) $((3==3)) $((3!=3))',
    'echo $((2&&0)) $((0||3)) $((!0)) $((!5))',
    'echo $((1?22:33)) $((0?22:33)) $(( 1 ? 2 : 3 ? 4 : 5 ))',
    'echo $((010)) $((0x1F)) $((0XfF))',
    'x=5; echo $((x+1)) $(($x+1))',
    'echo $((nosuch+1))',
    'x=5; echo $(( x > 3 ? x*2 : 0 ))',
    'echo $((9223372036854775807+1))',
    'echo $((0 && 1/0)) $((1 || 1/0))',
    'echo $(( $(echo 3) + 4 ))',
    'echo $((- -5)) $((+ +5)) $((!!5)) $(( ~ ~ 0 )) $((2 + -3))',
    'x=010; echo $((x))',
    'i=0; i=$((i+1)); i=$((i+1)); echo $i',
    'echo a; echo $((1/0)); echo b',
    'x=abc; echo $((x+1))',
    'echo $((1+))',
    'echo $((2**10))',
    'echo $((x=5)); echo "$x"',
    'x=10; echo $((x+=2)) $((x-=3)) $((x*=2)) $((x/=4)) $((x%=4)); echo $x',
    'x=1; echo $((x<<=4)) $((x>>=1)) $((x|=1)) $((x&=2)) $((x^=7))',
    'echo $((a=b=3)); echo "$a $b"',
    'echo $((y = 1 ? 2 : 3)); echo $y',
    'x=5; echo $(( x>0 ? (x=100) : 0 )); echo $x',
    'a=3; echo $((a += a += 1)); echo $a',
    'i=0; while [ $i -lt 3 ]; do i=$((i+1)); done; echo $i',
    'echo $((5=3))',
    'echo $((x=))',
    'echo ~',
    'echo ~/foo',
    'echo a~ ~~ x~/y',
    'echo "~" "~/a"',
    'echo ~root ~root/bin',
    'echo ~nosuchuser_zzz',
    'P=~/a:~root:b; echo "$P"',
    'echo ${u:-~}',
    'echo $((~5)) $((~0))',
    'x=g; f() { local x=in; echo $x; }; f; echo $x',
    'f() { local a b; a=1; b=2; echo "$a-$b"; }; f; echo "[$a][$b]"',
    'x=1; f() { local x=2; g; }; g() { echo $x; }; f',
    'n=5; f() { local n=$((n+1)); echo $n; }; f; echo $n',
    'x=keep; f() { local x; echo "[$x]"; }; f; echo $x',
    'set -o errexit; false; echo after',
    'set -o errexit; if true; then echo c; false; fi || echo rec; echo done',
    'set +o errexit; false; echo after',
    'set -o nounset; echo "${x:-ok}"; echo $undef; echo no',
    'type echo set if',
    'type ls',
    'f() { :; }; type f',
    'type nosuchcmd_zzz',
    'command -v echo',
    'command -v ls',
    'f() { :; }; command -v f',
    'command -v nosuchcmd_zzz; echo "rc=$?"',
    'echo() { echo no; }; command echo hi',
    'cd() { echo CDFUNC; }; cd /tmp; echo after',
    'true() { echo TF; }; true; echo "rc=$?"',
    'greet() { echo "hi $1"; }; greet world',
    'command -V echo',
    'command -V set',
    'command -V if',
    'command -V nosuch_zz; echo "rc=$?"',
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
    "n=0; trap 'n=1' TERM; kill -TERM $$; echo n=$n",
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
    # alias substitution happens at lex time and only affects *later* lines, so a
    # command-position name on a subsequent line is replaced by its value: a plain
    # command, a recursion-guarded self-reference, a nested chain, injected
    # reserved words, the trailing-<blank> argument chain, and never a quoted name,
    # a reserved word, an argument, or a case subject/pattern. Only stdout + exit
    # status are compared, so "not found" diagnostics on stderr are moot.
    "alias g=echo\ng hi",
    "alias g=echo\ng a b c",
    'alias g=echo; g hi',
    "alias echo='echo X'\necho hi",
    "alias a=echo\nalias b=a\nb two",
    "alias l='for i in 1 2'\nl\ndo echo $i; done",
    "alias first='echo '\nalias second=SECOND\nfirst second",
    "alias a='echo '\nalias b=hello\nalias c=world\na b c",
    "alias a='echo '\nalias b='B '\nalias c=CCC\na b c",
    "alias a='echo '\nalias b=hello\nalias hello=W\na b",
    "alias if=echo\nif hi",
    "alias x=echo\n\\x hi",
    "alias a=AAA\necho a",
    "alias a='echo '\nalias if=BAD\na if",
    "alias e=\ne echo hi",
    "alias p='echo hi | cat'\np",
    "alias greet='echo hello;'\ngreet world",
    "alias x=echo\ntrue && x A",
    "alias x=echo\nfalse | x B",
    "alias p=echo\ncase x in\n x) p ok;;\nesac",
    "alias r=BAD\ncase r in\n r) echo m;;\nesac",
    "alias p=echo\nfor n in 1 2; do p $n; done",
    "alias p=echo\nif true; then p hi; fi",
    "alias p=echo\n{ p hi; }",
    "alias p=echo\n( p hi )",
    "alias x=echo\ncommand x hi; echo rc=$?",
    # alias / unalias as builtins: listing (single-quoted name=value), querying,
    # removal, and type/command reporting. Multi-alias listings are sorted through
    # `sort` because rush sorts but dash lists in hash order.
    "alias ll=ls\nalias",
    "alias ll='ls -l'\nalias ll",
    "alias x=\"it's\"\nalias x",
    'alias',
    'alias nope; echo rc=$?',
    "alias a=1\nalias a=2\nalias a",
    "alias a=b=c\nalias a",
    "alias a=1\nalias b=2\nalias | sort",
    "alias a=1\nalias b=2\nunalias a\nalias",
    "alias a=1\nunalias -a\nalias",
    'unalias nope; echo rc=$?',
    'unalias; echo rc=$?',
    "alias ll='ls -l'\ntype ll",
    "alias ll='ls -l'\ncommand -v ll",
    "alias ll='ls -l'\ncommand -V ll",
    'type alias',
    # re-lexed input (eval, command substitution, a trap action) expands a
    # pre-existing alias, since the alias table is consulted wherever shell input
    # is tokenized.
    "alias g=echo\neval 'g hi'",
    "alias g=echo\neval g hi",
    "alias g=echo\necho \"$(g hi)\"",
    "alias g=echo\nx=$(g hi); echo $x",
    "alias g=echo\ntrap 'g bye' EXIT\necho body",
    # eval reads command by command (SourceRunner), so an alias or function it
    # defines shapes its own later lines. The result starts at success (empty/
    # comment-only input is 0) while $? stays live for the body;
    # break/continue/return/exit all propagate out.
    "eval 'alias e=echo\ne hi'",
    "eval 'g() {\necho hi\n}\ng'",
    "eval 'true\nfalse'; echo rc=$?",
    "false; eval ''; echo rc=$?",
    "false; eval '# c'; echo rc=$?",
    "eval 'false\n\n# c'; echo rc=$?",
    "false; eval 'echo $?'",
    "for i in 1 2 3; do eval 'echo $i\nbreak'; echo after; done; echo done",
    "for i in 1 2 3; do eval 'continue'; echo body $i; done; echo done",
    "f() { eval 'echo in\nreturn 5'; echo no; }; f; echo rc=$?",
    "eval 'echo a\nexit 7\necho b'; echo no",
    # a syntax error in eval is a special-builtin error: complete commands before
    # it run, then a non-interactive shell aborts with 2 (firing the EXIT trap);
    # a subshell aborts only itself.
    "eval 'echo a\nbad )'",
    "eval 'if'; echo after",
    "f() { eval 'if'; echo in; }; f; echo after",
    "trap 'echo bye' EXIT; eval 'if'; echo after",
    "( eval 'if' ); echo after",
    "eval 'echo a\nbad )'; echo after",
    # a pipeline stage may be any command, not only a simple command: a group,
    # subshell, if/while/for/case, or a function call, on either side of the `|`.
    '{ echo a; } | cat',
    'echo A | { echo G; cat; }',
    'echo Y | ( cat )',
    "printf '1\\n2\\n3\\n' | while read n; do echo \"got $n\"; done",
    'echo x | if cat; then echo T; fi',
    'echo z | case z in z) cat;; esac',
    'f() { cat; }; echo Y | f',
    'echo hi | { read x; echo \"[$x]\"; }',
    '{ echo a; echo b; } | wc -l',
    '( echo a; echo b ) | cat | cat',
    'echo a | cat | cat',
    # fd-duplication: n>&m / n<&m makes fd n a copy of fd m at that point in the
    # left-to-right fold; n>&- closes fd n (a write then fails, status 1); a fd
    # that is not open is status 2 and the shell continues; a non-numeric target
    # is a special-builtin error that aborts with 2.
    'echo o; { echo e >&2; } 2>&1',
    'echo x 2>&1 | cat',
    '{ echo a; echo b >&2; } 2>&1 | cat',
    'echo x 3>&1',
    'echo close >&-; echo after',
    'echo close >&-; echo "rc=$?"',
    'echo ok 2>&-; echo "rc=$?"',
    'true >&9; echo "rc=$?"',
    'echo x >&9; echo AFTER',
    'echo a; echo x >&9; echo b',
    'read x <&-; echo "after=$?"',
    "cat <&0 <<E\nhi\nE",
    'echo x >&foo; echo AFTER',
    "trap 'echo bye' EXIT; echo x >&foo"
  ].freeze

  corpus.each do |snippet|
    it "matches dash for: #{snippet}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end

  # NB: snippets avoid backslashes in echo output — dash's echo expands XSI
  # escapes (\t, \n, ...) while rush's echo defers that to Phase 2, so a
  # backslash in the echoed value would diverge on echo, not on read. The -r vs
  # non-r escape behaviour of read itself is covered by the unit spec.
  read_corpus = [
    ['read a b c; echo "$a-$b-$c"', "x y z w\n"],
    ['read a b; echo "[$a][$b]"', "only\n"],
    ['read x; echo "rc=$?"', ''],
    ['read first rest; echo "$rest"', "one two three\n"],
    ['while read l; do echo "got $l"; done', "p\nq\n"],
    ['IFS=:; read a b c; echo "[$a][$b][$c]"', "x:y:z\n"],
    ['IFS=:; read a b; echo "[$a][$b]"', "x:y:z\n"],
    ['IFS=:; read a b c; echo "[$a][$b][$c]"', "x::z\n"],
    ['IFS=:; read a b c; echo "[$a][$b][$c]"', ":x:\n"],
    ['IFS=" :"; read x y z; echo "[$x][$y][$z]"', "a :  b : c\n"]
  ].freeze

  read_corpus.each do |source, input|
    it "matches dash for: #{source} <- #{input.inspect}" do
      expect(rush(source, input)).to eq(dash(source, input))
    end
  end

  it 'sources a file the same as dash' do
    Tempfile.create(['rush_src', '.sh']) do |file|
      file.write("greet() { echo \"hi $1\"; }\nVALUE=42\n")
      file.flush
      source = ". #{file.path}; greet world; echo $VALUE"
      expect(rush(source)).to eq(dash(source))
    end
  end

  it 'expands a pre-existing alias inside a sourced file like dash' do
    Tempfile.create(['rush_alias', '.sh']) do |file|
      file.write("g infile\n")
      file.flush
      source = "alias g=echo\n. #{file.path}"
      expect(rush(source)).to eq(dash(source))
    end
  end

  # A sourced file is read command by command too, so an alias it defines affects
  # its own later lines, and `return` is bounded to the script (it becomes the
  # `.` status, the caller continuing). A syntax error mid-file runs the earlier
  # commands then aborts the non-interactive shell with 2 (special-builtin error).
  dot_cases = {
    'alias defined in file affects a later line' => ["alias g=echo\ng hi\n", '. %s'],
    'return is bounded to the dot script' => ["echo in\nreturn 4\necho no\n",
                                              'f() { . %s; echo after=$?; }; f; echo end=$?'],
    'return at top level continues the caller' => ["echo in\nreturn 3\necho no\n", '. %s; echo end=$?'],
    'break propagates to an enclosing loop' => ["echo $i\nbreak\n",
                                                'for i in 1 2 3; do . %s; echo loop; done; echo done'],
    'syntax error mid-file runs the rest then aborts' => ["echo a\nbad )\necho c\n", '. %s; echo after'],
    'a syntax error inside a subshell aborts only it' => ["if\n", '( . %s ); echo after']
  }

  dot_cases.each do |label, (body, template)|
    it "sources incrementally like dash: #{label}" do
      Tempfile.create(['rush_dot', '.sh']) do |file|
        file.write(body)
        file.flush
        source = format(template, file.path)
        expect(rush(source)).to eq(dash(source))
      end
    end
  end

  # A redirect whose target cannot be opened leaves a regular command unrun with
  # status 2 and the shell carries on; on a special builtin it aborts the shell
  # (firing the EXIT trap) — `nodir/` does not exist, `.` is a directory.
  def redirect_failure_snippets
    ['echo x >nodir/f; echo AFTER', 'echo x >nodir/f; echo $?', 'cat <nodir/f; echo $?',
     'echo x >.; echo $?', 'echo x >>nodir/f; echo $?', '>nodir/f; echo $?',
     'read x <nodir/f; echo AFTER', 'f(){ echo in; }; f >nodir/f; echo AFTER',
     ': >nodir/f; echo AFTER', 'export X=1 >nodir/f; echo AFTER', 'eval : >nodir/f; echo AFTER',
     'exec 3>nodir/f; echo AFTER', 'trap "echo T" EXIT; : >nodir/f; echo AFTER',
     '( : >nodir/f ); echo AFTER', 'true; : >nodir/f; echo unreached']
  end

  it 'handles a failed redirect open the same as dash (status 2; fatal on a special builtin)' do
    Dir.mktmpdir do |dir|
      redirect_failure_snippets.each do |snippet|
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "diverged on: #{snippet}"
      end
    end
  end

  def input_redirect_snippets
    ['while read v; do echo "<$v>"; done < in', 'if read a; then echo "got $a"; fi < in',
     '{ read p; read q; echo "$p-$q"; } < in', 'for w in one; do echo "$w"; done < in']
  end

  it 'feeds an input redirect into a compound command the same as dash' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'in'), "x\ny\n")
      input_redirect_snippets.each do |snippet|
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "diverged on: #{snippet}"
      end
    end
  end

  # A redirection's target is flushed+closed when the command finishes, so a
  # later command in the same invocation sees the data (the write file is opened
  # in sync mode, so a forked subshell's output survives its exit! too).
  def output_redirect_snippets
    ['echo x > f; cat f', '{ echo a; echo b; } > f; cat f', 'echo aaa > f; echo b > f; cat f',
     'echo a > f; echo b >> f; cat f', 'for i in 1 2 3; do echo $i; done > f; cat f',
     '( echo s1; echo s2 ) > f; cat f', '> f; cat f; echo "rc=$?"',
     'echo one > f; cat f; echo two > f; cat f', 'echo hi > f; read x < f; echo "[$x]"',
     '( for i in 1 2; do echo $i; done ) > f; wc -l < f', 'echo n > f; ( cat f; echo m ) > g; cat g',
     'echo a > f 2>&1; cat f', 'echo keep 2>&1 > f; cat f', '{ echo o; echo e >&2; } > f 2>&1; cat f',
     'ls /no_such_rush 2>f 1>&2; cat f']
  end

  it 'flushes a redirect target so a later command in the same shell sees it, like dash' do
    Dir.mktmpdir do |dir|
      output_redirect_snippets.each do |snippet|
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "diverged on: #{snippet}"
      end
    end
  end

  # Lowercase-only names keep byte-order sorting (rush) and LC_COLLATE sorting
  # (dash) in agreement, so these compare without forcing a locale.
  def glob_patterns
    ['echo *', 'echo *.txt', 'echo *.md', 'echo ?.txt', 'echo [ab].txt',
     'echo [!a].txt', 'echo sub/*', 'echo */*.txt', 'echo "*"', "echo '*'",
     'echo z*', 'set -f; echo *.txt', 'echo *.txt *.log', 'echo [a.txt',
     'echo a"*"', 'for f in *.txt; do echo "$f"; done', 'set -- *.txt; echo $#']
  end

  it 'expands pathname patterns the same as dash' do
    Dir.mktmpdir do |dir|
      %w[a.txt b.txt c.log file1 file2].each { |f| FileUtils.touch(File.join(dir, f)) }
      Dir.mkdir(File.join(dir, 'sub'))
      FileUtils.touch(File.join(dir, 'sub', 'x.txt'))
      glob_patterns.each do |pattern|
        source = "cd #{dir}; #{pattern}"
        expect(rush(source)).to eq(dash(source)), "diverged on: #{pattern}"
      end
    end
  end

  # Redirect-only `exec` makes the redirection permanent for the rest of the
  # shell, unlike a per-command redirect: the opened target must stay open so
  # later commands keep writing to / reading from it. The dup form (2>&1) opens
  # nothing, so it already persisted; a forked subshell's exec must not leak out.
  def exec_persist_snippets
    ['exec 4>&1; exec > f; echo one; echo two; exec 1>&4 4>&-; cat f',
     'exec 3> f; echo hi >&3; exec 3>&-; cat f',
     'echo seed > f; exec 4>&1; exec >> f; echo more; exec 1>&4 4>&-; cat f',
     'printf "a\nb\n" > in; exec < in; read x; read y; echo "$x-$y"',
     'exec 2>&1; echo viastderr >&2', '( exec > sub; echo inside ); echo outside',
     'exec 4>&1; exec > f; echo first; exec > g; echo second; exec 1>&4 4>&-; cat f; cat g']
  end

  it 'makes redirect-only exec persist for the rest of the shell, like dash' do
    Dir.mktmpdir do |dir|
      exec_persist_snippets.each do |snippet|
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "diverged on: #{snippet}"
      end
    end
  end

  # A function runs in the current shell, so a redirect on the *call* binds the
  # whole body (output, stderr dup, nested calls) and is torn down on return —
  # an `exec` inside `f >file` is scoped to that redirect (undone after f), but an
  # `exec` inside a call with no redirect persists (the body shares the shell io).
  def function_redirect_snippets
    ['f(){ echo body; }; f > f.txt; echo after; cat f.txt',
     'f(){ echo x; return 3; }; f > f.txt; echo "rc=$?"; cat f.txt',
     'f(){ echo out; echo err >&2; }; f > f.txt 2>&1; cat f.txt',
     'f(){ echo a; echo b; }; f > f.txt; f >> f.txt; cat f.txt',
     'f(){ echo outer; echo inner > i.txt; }; f > o.txt; printf "[o]"; cat o.txt; printf "[i]"; cat i.txt',
     'g(){ echo from-g; }; f(){ echo from-f; g; }; f > f.txt; cat f.txt',
     'exec 4>&1; f(){ exec > g.txt; }; f; echo A; exec 1>&4 4>&-; echo B; printf "G="; cat g.txt',
     'exec 4>&1; f(){ echo first; exec > o.txt; echo second; }; f > f.txt; echo A; exec 1>&4 4>&-; ' \
     'printf "F="; cat f.txt; printf "O="; cat o.txt']
  end

  it 'binds a redirect on a function call to the whole body, like dash' do
    Dir.mktmpdir do |dir|
      function_redirect_snippets.each do |snippet|
        source = "cd #{dir}; #{snippet}"
        expect(rush(source)).to eq(dash(source)), "diverged on: #{snippet}"
      end
    end
  end
end
