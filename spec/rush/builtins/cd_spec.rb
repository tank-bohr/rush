# frozen_string_literal: true

RSpec.describe Rush::Builtins::Cd do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new('HOME' => '/home/test') }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def cd(*args)
    described_class.new(executor, ['cd', *args], io).call
  end

  it 'changes to the given directory and updates PWD/OLDPWD' do
    executor.state.variables.move_to('/start')
    expect(cd('/some/dir')).to be_success
    expect(system.chdirs).to eq(['/some/dir'])
    expect(env.get('PWD')).to eq('/some/dir')
    expect(env.get('OLDPWD')).to eq('/start')
  end

  it 'resolves a relative directory against the logical pwd' do
    executor.state.variables.move_to('/a/b')
    cd('..')
    expect(env.get('PWD')).to eq('/a')
  end

  it 'defaults to HOME when no operand is given' do
    cd
    expect(system.chdirs).to eq(['/home/test'])
  end

  it 'changes to OLDPWD and prints the destination for cd -' do
    executor.state.variables.move_to('/start')
    cd('/next')
    expect(cd('-')).to be_success
    expect(system.chdirs).to eq(['/next', '/start'])
    expect(env.get('PWD')).to eq('/start')
    expect(env.get('OLDPWD')).to eq('/next')
    expect(system.stdout.string).to eq("/start\n")
  end

  it 'uses the logical current directory for cd - before OLDPWD exists' do
    expect(cd('-')).to be_success
    expect(system.chdirs).to eq(['/home/test'])
    expect(system.stdout.string).to eq("/home/test\n")
  end

  it 'reports an error when cd - cannot change to OLDPWD' do
    executor.state.variables.move_to('/gone')
    executor.state.variables.move_to('/middle')
    system.fail_chdir_with(Errno::ENOENT)
    expect(cd('-')).not_to be_success
    expect(system.stderr.string).to eq("rush: cd: /gone: No such file or directory\n")
    expect(system.stdout.string).to be_empty
  end

  it 'fails when HOME is unset and no operand is given' do
    bare = Rush::Executor.new(system: system, state: Rush::ShellState.new(environment: Rush::Environment.new({})))
    expect(described_class.new(bare, ['cd'], io).call).not_to be_success
    expect(system.stderr.string).to include('HOME not set')
  end

  it 'reports an error for a missing directory' do
    system.fail_chdir_with(Errno::ENOENT)
    expect(cd('/nope')).not_to be_success
    expect(system.stderr.string).to eq("rush: cd: /nope: No such file or directory\n")
  end
end
