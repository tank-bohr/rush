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
    state.options.set(:nounset, true)
    expect(state.options.on?(:nounset)).to be(true)
    state.options.set(:nounset, false)
    expect(state.options.on?(:nounset)).to be(false)
  end

  it 'tracks loop nesting depth for break/continue' do
    state = described_class.new
    expect(state.loops.any?).to be(false)
    state.loops.enter
    state.loops.enter
    expect([state.loops.depth, state.loops.any?]).to eq([2, true])
    state.loops.leave
    expect(state.loops.depth).to eq(1)
  end

  it 'resets the loop depth across a function/subshell boundary, then restores it' do
    state = described_class.new
    state.loops.enter
    inner = state.loops.without { state.loops.depth }
    expect([inner, state.loops.depth]).to eq([0, 1])
  end
end
