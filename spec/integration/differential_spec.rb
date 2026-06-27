# frozen_string_literal: true

require 'open3'
require 'tempfile'

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
    'x=abc; echo "${x#xyz}|${x#*}|${x##*}"'
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
    ['while read l; do echo "got $l"; done', "p\nq\n"]
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
end
