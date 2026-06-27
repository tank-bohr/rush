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
end
