# frozen_string_literal: true

RSpec.describe 'rush end-to-end (Phase 0)' do
  def run(source)
    system = FakeSystemCalls.new
    code = Rush::CLI.run(['-c', source], system: system)
    [system.stdout.string, code]
  end

  it 'runs the null and boolean builtins, propagating the last status' do
    output, code = run(': ; true ; false')
    expect(output).to eq('')
    expect(code).to eq(1)
  end

  it 'runs a sequence of commands in order' do
    output, code = run('echo one; echo two')
    expect(output).to eq("one\ntwo\n")
    expect(code).to eq(0)
  end
end
