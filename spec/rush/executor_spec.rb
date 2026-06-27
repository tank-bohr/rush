# frozen_string_literal: true

RSpec.describe Rush::Executor do
  let(:system) { FakeSystemCalls.new }

  def state(vars = {}) = Rush::ShellState.new(environment: Rush::Environment.new(vars))
  def build(state, **extra) = described_class.new(system: system, state: state, **extra)

  it 'defaults the builtin registry and sets up the io table' do
    executor = build(state)
    expect(executor.builtins.key?('echo')).to be(true)
    expect(executor.io).to be_a(Rush::IoTable)
  end

  it 'backfills the logical pwd from the OS when the environment has none' do
    expect(build(state).state.pwd).to eq('/home/test')
  end

  it 'keeps the environment PWD when present' do
    expect(build(state('PWD' => '/x')).state.pwd).to eq('/x')
  end

  it 'records the last status when running a node' do
    target = state
    build(target).run(Rush::AST::SimpleCommand.new([], [Rush::AST::Word.literal('false')], []))
    expect(target.last_status.exitstatus).to eq(1)
  end

  it 'accepts an injected builtin registry' do
    registry = Rush::Builtins::Registry.new
    expect(build(state, builtins: registry).builtins).to be(registry)
  end
end
