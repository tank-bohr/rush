# frozen_string_literal: true

RSpec.describe 'rush end-to-end (Phase 1, Slice 1)' do
  def run(source)
    system = FakeSystemCalls.new
    code = Rush::CLI.run(['-c', source], system: system)
    [system.stdout.string, code, system]
  end

  it 'runs the null and boolean builtins, propagating the last status' do
    output, code = run(': ; true ; false')
    expect(output).to eq('')
    expect(code).to eq(1)
  end

  it 'short-circuits && and || by exit status' do
    expect(run('true && echo yes').first).to eq("yes\n")
    expect(run('false || echo no').first).to eq("no\n")
    expect(run('false && echo skipped').first).to eq('')
  end

  it 'runs a sequence of commands in order' do
    expect(run('echo one; echo two').first).to eq("one\ntwo\n")
  end

  it 'redirects builtin output to a file' do
    _out, code, system = run('echo saved > /tmp/out')
    expect(code).to eq(0)
    expect(system.files['/tmp/out'].string).to eq("saved\n")
  end

  it 'removes quotes and keeps quoted blanks within one argument' do
    expect(run('echo "hello   world"').first).to eq("hello   world\n")
    expect(run("echo 'a;b'").first).to eq("a;b\n")
    expect(run('echo a"b c"d').first).to eq("ab cd\n")
  end

  it 'expands variables, defaults and special parameters' do
    expect(run('x=5; echo "x=$x"').first).to eq("x=5\n")
    expect(run('echo ${UNSET:-fallback}').first).to eq("fallback\n")
    expect(run('true; echo $?').first).to eq("0\n")
  end

  it 'reports an error for an unset parameter with :? and exits non-zero' do
    output, code = run('echo ${MISSING:?required}')
    expect(output).to eq('')
    expect(code).not_to eq(0)
  end

  it 'field-splits unquoted expansions but keeps quoted ones intact' do
    expect(run('x="a   b   c"; echo $x').first).to eq("a b c\n")
    expect(run('x="a b"; echo "[$x]"').first).to eq("[a b]\n")
    expect(run('e=; echo "[$e]"').first).to eq("[]\n")
  end

  it 'runs if/elif/else and brace groups' do
    expect(run('if true; then echo yes; fi').first).to eq("yes\n")
    expect(run('if false; then echo a; elif true; then echo b; else echo c; fi').first).to eq("b\n")
    expect(run('{ echo one; echo two; }').first).to eq("one\ntwo\n")
  end

  it 'negates a pipeline status with !' do
    expect(run('! false')[1]).to eq(0)
    expect(run('! true')[1]).to eq(1)
  end

  it 'runs while/until loops with break and continue' do
    expect(run('while false; do echo x; done; echo after').first).to eq("after\n")
    expect(run('echo a; while true; do echo once; break; done; echo b').first).to eq("a\nonce\nb\n")
    expect(run('until true; do echo never; done; echo z').first).to eq("z\n")
  end

  it 'runs for loops over a word list, splitting unquoted expansions' do
    expect(run('for i in 1 2 3; do echo $i; done').first).to eq("1\n2\n3\n")
    expect(run('s="x y"; for w in $s; do echo $w; done').first).to eq("x\ny\n")
  end

  it 'runs case statements with glob and alternation patterns' do
    expect(run('case hi in h*) echo glob;; *) echo no;; esac').first).to eq("glob\n")
    expect(run('case b in a) echo a;; b|c) echo bc;; esac').first).to eq("bc\n")
    expect(run('case z in a) echo a;; esac; echo done').first).to eq("done\n")
  end

  it 'defines and calls functions with arguments and return' do
    expect(run('greet() { echo "hi $1"; }; greet world').first).to eq("hi world\n")
    expect(run('f() { return 3; }; f; echo $?').first).to eq("3\n")
    expect(run('count() { echo $#; }; count a b c').first).to eq("3\n")
  end

  it 'evaluates conditionals with the test builtin and its [ alias' do
    expect(run('[ -n nonempty ] && echo yes').first).to eq("yes\n")
    expect(run('[ "$x" = "" ] && echo empty').first).to eq("empty\n")
    expect(run('test 3 -lt 5 && echo less').first).to eq("less\n")
    expect(run('if [ 2 -gt 1 ]; then echo big; fi').first).to eq("big\n")
    expect(run('[ bad arg here ]; echo $?').first).to eq("2\n")
  end

  it 'sets and shifts the positional parameters' do
    expect(run('set a b c; echo "$1 $3 $#"').first).to eq("a c 3\n")
    expect(run('set a b c; shift 2; echo "$1 $#"').first).to eq("c 1\n")
    expect(run('set -- x; echo "$# $1"').first).to eq("1 x\n")
  end

  it 'expands "$@" to one field per parameter and "$*" to a joined field' do
    expect(run('set a b c; for x in "$@"; do echo "[$x]"; done').first).to eq("[a]\n[b]\n[c]\n")
    expect(run('set "a b" c; for x in "$@"; do echo "[$x]"; done').first).to eq("[a b]\n[c]\n")
    expect(run('set --; for x in "$@"; do echo no; done; echo done').first).to eq("done\n")
    expect(run('set a b c; echo "$*"').first).to eq("a b c\n")
    expect(run('set a b c; echo "pre$@post"').first).to eq("prea b cpost\n")
  end

  it 'exports and unsets variables' do
    expect(run('export X=hi; echo $X').first).to eq("hi\n")
    expect(run('Y=keep; unset Y; echo "[$Y]"').first).to eq("[]\n")
  end
end
