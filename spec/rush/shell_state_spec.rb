# frozen_string_literal: true

RSpec.describe Rush::ShellState do
  it 'defaults to fresh variables, a success status, process ids and the name rush' do
    state = described_class.new
    expect([state.name, state.shell_pid, state.parent_pid, state.variables.get('PPID')]).to eq(['rush', 0, 0, '0'])
    expect(state.last_status).to be_success
    expect(state.variables).to be_a(Rush::ShellVariables)
    expect(state.parameters).to be_a(Rush::ShellParameters)
  end

  it 'accepts an injected environment, name and process ids' do
    env = Rush::Environment.new('X' => '1')
    state = described_class.new(environment: env, name: 'sh', pids: Rush::ShellProcessIds.new(4242, 3131))
    expect(state.variables.get('X')).to eq('1')
    actual = [state.name, state.shell_pid, state.parent_pid, state.variables.get('PPID')]
    expect(actual).to eq(['sh', 4242, 3131, '3131'])
  end

  it 'toggles and reports shell options' do
    state = described_class.new
    state.options.set(:nounset, true)
    expect(state.options.on?(:nounset)).to be(true)
    state.options.set(:nounset, false)
    expect(state.options.on?(:nounset)).to be(false)
  end

  it 'seeds OPTIND at 1 with a fresh getopts state and an empty trap table' do
    state = described_class.new
    expect([state.variables.get('OPTIND'), state.traps.listing]).to eq(['1', []])
    expect(state.getopts).to be_a(Rush::GetoptsState)
  end

  it 'seeds the positional parameters from the constructor, empty by default' do
    expect(described_class.new(positional: %w[a b]).positional.to_a).to eq(%w[a b])
    expect(described_class.new.positional.empty?).to be(true)
  end

  it 'starts with empty function, alias and command-hash tables' do
    state = described_class.new
    expect([state.functions.key?('f'), state.aliases.key?('a'), state.command_hash]).to eq([false, false, {}])
  end

  it 'flips options through set_option like the set builtin' do
    state = described_class.new
    state.set_option(:errexit, true)
    expect(state.options.on?(:errexit)).to be(true)
    state.set_option(:errexit, false)
    expect(state.options.on?(:errexit)).to be(false)
  end

  it 'mirrors allexport onto the variable table (set -a)' do
    state = described_class.new(environment: Rush::Environment.new({}))
    state.set_option(:allexport, true)
    state.variables.assign('N', '1')
    expect(state.variables.exported).to include('N' => '1')
  end

  it 'does not touch the allexport mirror for other options' do
    state = described_class.new(environment: Rush::Environment.new({}))
    state.set_option(:errexit, true)
    state.variables.assign('N', '1')
    expect(state.variables.exported).not_to include('N' => '1')
  end

  it 'turns the allexport mirror back off (set +a)' do
    state = described_class.new(environment: Rush::Environment.new({}))
    state.set_option(:allexport, true)
    state.set_option(:allexport, false)
    state.variables.assign('N', '1')
    expect(state.variables.exported).not_to include('N' => '1')
  end

  it 'tracks LINENO through record_lineno' do
    state = described_class.new(environment: Rush::Environment.new({}))
    state.record_lineno(4)
    expect(state.variables.get('LINENO')).to eq('4')
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
