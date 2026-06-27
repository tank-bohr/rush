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
end
