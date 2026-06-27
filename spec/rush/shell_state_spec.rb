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
end
