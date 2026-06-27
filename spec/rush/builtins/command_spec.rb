# frozen_string_literal: true

RSpec.describe Rush::Builtins::Command do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new('PATH' => '/usr/bin')) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['command', *args], io).call

  it 'prints the name for -v of a builtin and the path for an external' do
    system.register('/usr/bin/ls', executable: true)
    run('-v', 'echo')
    run('-v', 'ls')
    expect(system.stdout.string).to eq("echo\n/usr/bin/ls\n")
  end

  it 'fails with 127 for -v of an unknown or missing name' do
    expect([run('-v', 'nope_zzz').exitstatus, run('-v').exitstatus]).to eq([127, 127])
  end

  it 'runs a builtin, bypassing a shadowing function' do
    state.functions.define('echo', Rush::AST::SimpleCommand.new([], [], []))
    run('echo', 'hi')
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'runs an external command, bypassing functions' do
    external = instance_double(Rush::External, call: Rush::Status.success)
    allow(Rush::External).to receive(:new).and_return(external)
    expect(run('extprog', 'arg')).to be_success
    expect(Rush::External).to have_received(:new).with(executor, %w[extprog arg], io, kind_of(Hash))
  end

  it 'returns success when given no name to run' do
    expect(run).to be_success
  end
end
