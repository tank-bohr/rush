# frozen_string_literal: true

RSpec.describe Rush::Builtins::Hash do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new('PATH' => '/bin') }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['hash', *args], io).call
  end

  before do
    system.register('/bin/ls', executable: true)
    system.register('/bin/cat', executable: true)
  end

  it 'records a PATH command and lists it as its full path' do
    expect(run('ls')).to be_success
    expect(state.command_hash).to eq('ls' => '/bin/ls')
    run
    expect(system.stdout.string).to eq("/bin/ls\n")
  end

  it 'lists the cached locations sorted by name' do
    run('ls', 'cat')
    system.stdout.truncate(0)
    system.stdout.rewind
    run
    expect(system.stdout.string).to eq("/bin/cat\n/bin/ls\n")
  end

  it 'lists nothing for an empty cache' do
    expect(run).to be_success
    expect(system.stdout.string).to be_empty
  end

  it 'forgets every cached location with -r' do
    run('ls')
    expect(run('-r')).to be_success
    expect(state.command_hash).to be_empty
  end

  it 'ignores a builtin name without caching it' do
    expect(run('echo')).to be_success
    expect(state.command_hash).to be_empty
  end

  it 'ignores a name containing a slash' do
    expect(run('/bin/ls')).to be_success
    expect(state.command_hash).to be_empty
  end

  it 'fails with status 1 and a message on an unresolvable name' do
    expect(run('nosuch_zzz')).not_to be_success
    expect(system.stderr.string).to include('hash: nosuch_zzz: not found')
  end
end
