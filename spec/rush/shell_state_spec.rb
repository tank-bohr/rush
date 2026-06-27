# frozen_string_literal: true

RSpec.describe Rush::ShellState do
  it 'defaults to a fresh environment, a success status and the name rush' do
    state = described_class.new
    expect(state.name).to eq('rush')
    expect(state.last_status).to be_success
    expect(state.environment).to be_a(Rush::Environment)
  end

  it 'accepts an injected environment and name' do
    env = Rush::Environment.new({})
    state = described_class.new(environment: env, name: 'sh')
    expect(state.environment).to be(env)
    expect(state.name).to eq('sh')
  end

  it 'toggles and reports shell options' do
    state = described_class.new
    state.set_option(:nounset, true)
    expect(state.option?(:nounset)).to be(true)
    state.set_option(:nounset, false)
    expect(state.option?(:nounset)).to be(false)
  end

  it 'tracks loop nesting depth for break/continue' do
    state = described_class.new
    expect(state.in_loop?).to be(false)
    state.enter_loop
    state.enter_loop
    expect([state.loop_depth, state.in_loop?]).to eq([2, true])
    state.leave_loop
    expect(state.loop_depth).to eq(1)
  end

  it 'resets the loop depth across a function/subshell boundary, then restores it' do
    state = described_class.new
    state.enter_loop
    inner = state.without_loops { state.loop_depth }
    expect([inner, state.loop_depth]).to eq([0, 1])
  end
end
