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
end
