# frozen_string_literal: true

require 'open3'

# Differential tests: each snippet must produce the same stdout and exit status
# under rush as under dash, the POSIX oracle. Skipped when dash is unavailable.
# These run the real exe/rush in a child process, so they do not contribute to
# SimpleCov; the in-process unit specs own coverage.
RSpec.describe 'rush vs dash (differential)' do
  def project_root = File.expand_path('../..', __dir__)

  def rush(source)
    out, _err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rush', '-c', source, chdir: project_root)
    [out, status.exitstatus]
  end

  def dash(source)
    out, _err, status = Open3.capture3('dash', '-c', source)
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
    'set --; echo "z$@w"'
  ].freeze

  corpus.each do |snippet|
    it "matches dash for: #{snippet}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end
end
