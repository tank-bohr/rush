# frozen_string_literal: true

RSpec.describe Rush::Builtins::Unset do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new({}) }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['unset', *args], io).call

  it 'removes a variable' do
    env.assign('X', '1')
    expect(run('X')).to be_success
    expect(env.get('X')).to be_nil
  end

  it 'treats a -v flag as a variable unset' do
    env.assign('X', '1')
    run('-v', 'X')
    expect(env.get('X')).to be_nil
  end

  it 'removes a function with -f' do
    state.functions.define('f', Rush::AST::SimpleCommand.new([], [], []))
    run('-f', 'f')
    expect(state.functions.key?('f')).to be(false)
  end

  it 'succeeds as a no-op when given no operands' do
    expect(run).to be_success
  end
end
