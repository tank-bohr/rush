# frozen_string_literal: true

require 'open3'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

# Differential tests: each snippet must produce the same stdout and exit status
# under rush as under dash, the POSIX oracle. Skipped when dash is unavailable.
# These run the real exe/rush in a child process, so they do not contribute to
# SimpleCov; the in-process unit specs own coverage.
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
    # is tokenized. (An alias *defined inside* an eval string or sourced file does
    # not affect later lines of that same construct: rush parses each as one unit
    # where dash reads them incrementally — tracked as a future incremental-eval
    # slice. Command substitution parses as one unit in dash too, so it agrees.)
    "alias g=echo\neval 'g hi'",
    "alias g=echo\neval g hi",
    "alias g=echo\necho \"$(g hi)\"",
    "alias g=echo\nx=$(g hi); echo $x",
    "alias g=echo\ntrap 'g bye' EXIT\necho body"
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
end
