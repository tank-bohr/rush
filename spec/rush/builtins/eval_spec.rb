# frozen_string_literal: true

RSpec.describe Rush::Builtins::Eval do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['eval', *args], io).call

  it 'parses and runs the joined arguments in the current shell' do
    expect(run('echo', 'hi')).to be_success
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'returns the status of the evaluated command' do
    expect(run('false')).not_to be_success
  end

  it 'sees and mutates the current environment' do
    run('X=set')
    expect(state.environment.get('X')).to eq('set')
  end

  it 'raises a BuiltinError on a syntax error (a special builtin aborts the shell)' do
    expect { run('if') }.to raise_error(Rush::BuiltinError, /eval/)
  end

  it 'propagates exit from the evaluated input' do
    expect { run('exit 4') }.to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(4) }
  end

  it 'is a no-op success when given no arguments' do
    expect(run).to be_success
  end

  it 'reads command by command, so an alias defined inside affects a later line' do
    expect(run("alias g=echo\ng hi")).to be_success
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'runs the commands before a later syntax error, then aborts' do
    expect { run("echo a\nbad )") }.to raise_error(Rush::BuiltinError)
    expect(system.stdout.string).to eq("a\n")
  end

  it 'returns success for empty input even after a failing command' do
    state.last_status = Rush::Status.new(1)
    expect(run('')).to be_success
  end

  it 'propagates break from the evaluated input to an enclosing loop' do
    state.enter_loop
    expect { run('break') }.to raise_error(Rush::LoopControl)
  end

  it 'propagates return from the evaluated input (transparent, unlike dot)' do
    expect { run('return 5') }.to raise_error(Rush::ReturnSignal) { |e| expect(e.code).to eq(5) }
  end
end
