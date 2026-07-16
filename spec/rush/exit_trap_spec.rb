# frozen_string_literal: true

RSpec.describe Rush::ExitTrap do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:runner) { executor.trap_runner }

  def exit_trap(action)
    runner.set('EXIT', action)
  end

  it 'passes the terminating code through untouched without a trap' do
    expect(runner.run_exit_trap(5)).to eq(5)
    expect(system.stdout.string).to be_empty
  end

  it 'runs the action with $? holding the terminating status (POSIX 2.14), exactly once' do
    exit_trap('echo st=$?')
    expect(runner.run_exit_trap(3)).to eq(3)
    expect(system.stdout.string).to eq("st=3\n")
    expect(runner.run_exit_trap(4)).to eq(4)
    expect(system.stdout.string).to eq("st=3\n")
  end

  it 'lets an exit inside the trap override the terminating code' do
    exit_trap('exit 9')
    expect(runner.run_exit_trap(3)).to eq(9)
  end

  it 'preserves the terminating code against a return in the body' do
    exit_trap('return')
    expect(runner.run_exit_trap(3)).to eq(3)
  end

  it 'preserves the terminating code against loop control in the body' do
    exit_trap('break')
    expect(runner.run_exit_trap(7)).to eq(7)
  end

  it 'aborts to 2 with a diagnostic on a fatal error inside the body' do
    exit_trap('do')
    expect(runner.run_exit_trap(3)).to eq(2)
    expect(system.stderr.string).to include('rush: ')
  end

  it 'converts a special-builtin redirect failure in the body to status 2 (POSIX 2.8.1)' do
    allow(system).to receive(:open_file).and_raise(Errno::EACCES)
    exit_trap(': > blocked')
    expect(runner.run_exit_trap(3)).to eq(2)
    expect(state.last_status.exitstatus).to eq(2)
    expect(system.stderr.string).to match(/\Arush: /)
  end
end
