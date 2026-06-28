# frozen_string_literal: true

RSpec.describe Rush::Builtins::Type do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new('PATH' => '/usr/bin')) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['type', *args], io).call
  end

  it 'reports each name with its kind' do
    expected = "echo is a shell builtin\nset is a special shell builtin\nif is a shell keyword\n"
    expect(run('echo', 'set', 'if')).to be_success
    expect(system.stdout.string).to eq(expected)
  end

  it 'reports a PATH executable' do
    system.register('/usr/bin/ls', executable: true)
    expect(run('ls')).to be_success
    expect(system.stdout.string).to eq("ls is /usr/bin/ls\n")
  end

  it 'reports an unknown name on stdout and fails with 127' do
    expect(run('nope_zzz').exitstatus).to eq(127)
    expect(system.stdout.string).to eq("nope_zzz: not found\n")
  end

  it 'reports an alias as an alias for its value' do
    state.aliases.define('ll', 'ls -l')
    expect(run('ll')).to be_success
    expect(system.stdout.string).to eq("ll is an alias for ls -l\n")
  end
end
