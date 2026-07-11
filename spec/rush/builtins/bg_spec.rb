# frozen_string_literal: true

RSpec.describe Rush::Builtins::Bg do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def bg(*args)
    described_class.new(executor, ['bg', *args], io).call
  end

  before do
    executor.jobs.control.engage(nil)
    executor.jobs.adopt_stopped([50, 51], 20, 'sleep 100 | cat')
  end

  it 'resumes the group: SIGCONT to -pgid, entry Running, "[n] text" printed, status 0' do
    expect(bg('%1')).to be_success
    expect(system.kills).to eq([['CONT', -50]])
    expect(executor.jobs.current.running?).to be(true)
    expect(system.stdout.string).to eq("[1] sleep 100 | cat\n")
  end

  it 'leaves the terminal with the shell (no handover, no reclaim)' do
    tty_system = FakeSystemCalls.new(tty: true)
    tty_executor = Rush::Executor.new(system: tty_system, state: state)
    tty_executor.job_control.enable(tty_system.stderr)
    tty_executor.jobs.adopt_stopped([50], 20, 'sleep 9')
    described_class.new(tty_executor, %w[bg %1], Rush::IoTable.standard(tty_system)).call
    expect(tty_system.handovers).to eq([4242])
  end

  it 'clears the pending notification: bg own line is the announcement' do
    expect(executor.jobs.current.changed).to be(true)
    bg('%1')
    expect(executor.jobs.current.changed).to be(false)
  end
end
