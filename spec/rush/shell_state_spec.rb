# frozen_string_literal: true

RSpec.describe Rush::ShellState do
  it 'defaults to fresh variables, a success status and the name rush' do
    state = described_class.new
    expect([state.name, state.shell_pid]).to eq(['rush', 0])
    expect(state.last_status).to be_success
    expect(state.variables).to be_a(Rush::ShellVariables)
    expect(state.parameters).to be_a(Rush::ShellParameters)
  end

  it 'accepts an injected environment, name and shell pid' do
    env = Rush::Environment.new('X' => '1')
    state = described_class.new(environment: env, name: 'sh', shell_pid: 4242)
    expect(state.variables.get('X')).to eq('1')
    expect([state.name, state.shell_pid]).to eq(['sh', 4242])
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

  it 'brackets loop depth and restores it after errors' do
    state = described_class.new
    expect { state.with_loop { raise Rush::BreakSignal, 1 } }.to raise_error(Rush::BreakSignal)
    expect(state.loops.depth).to eq(0)
  end

  it 'preserves the last status around a block' do
    state = described_class.new
    state.record_status(Rush::Status.new(7))
    result = state.preserve_status do
      state.record_status(Rush::Status.new(2))
      :ran
    end
    expect([result, state.last_status.exitstatus]).to eq([:ran, 7])
  end

  it 'records the most recent background pid for $!' do
    state = described_class.new
    expect(state.parameters.resolve('!')).to be_nil
    state.record_background_pid(1234)
    expect([state.last_background_pid, state.parameters.resolve('!')]).to eq([1234, '1234'])
  end

  it 'brackets function frames around locals, loops and positionals' do
    state = described_class.new(environment: Rush::Environment.new('x' => 'global'))
    state.positional.replace(%w[outer])
    state.loops.enter

    result = state.with_function_frame(%w[arg]) do
      state.variables.declare_local_operand('x=local')
      [state.positional.to_a, state.loops.depth, state.variables.get('x')]
    end

    expect(result).to eq([%w[arg], 0, 'local'])
    expect([state.positional.to_a, state.loops.depth, state.variables.get('x')]).to eq([%w[outer], 1, 'global'])
  end
end
