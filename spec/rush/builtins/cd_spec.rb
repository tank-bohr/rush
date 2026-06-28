# frozen_string_literal: true

RSpec.describe Rush::Builtins::Cd do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new('HOME' => '/home/test') }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def cd(*args) = described_class.new(executor, ['cd', *args], io).call

  it 'changes to the given directory and updates PWD/OLDPWD' do
    state.move_to('/start')
    expect(cd('/some/dir')).to be_success
    expect(system.chdirs).to eq(['/some/dir'])
    expect(env.get('PWD')).to eq('/some/dir')
    expect(env.get('OLDPWD')).to eq('/start')
  end

  it 'resolves a relative directory against the logical pwd' do
    state.move_to('/a/b')
    cd('..')
    expect(env.get('PWD')).to eq('/a')
  end

  it 'defaults to HOME when no operand is given' do
    cd
    expect(system.chdirs).to eq(['/home/test'])
  end

  it 'fails when HOME is unset and no operand is given' do
    bare = Rush::Executor.new(system: system, state: Rush::ShellState.new(environment: Rush::Environment.new({})))
    expect(described_class.new(bare, ['cd'], io).call).not_to be_success
    expect(system.stderr.string).to include('HOME not set')
  end

  it 'reports an error for a missing directory' do
    system.fail_chdir_with(Errno::ENOENT)
    expect(cd('/nope')).not_to be_success
    expect(system.stderr.string).to include('No such file or directory')
  end
end
