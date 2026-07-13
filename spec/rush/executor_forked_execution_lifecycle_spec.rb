# frozen_string_literal: true

RSpec.describe Rush::Executor do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { described_class.new(system: system, state: state) }

  def trace(events, receiver, method, event)
    allow(receiver).to receive(method).and_wrap_original do |original, *args, &block|
      events << event
      original.call(*args, &block)
    end
  end

  def node(events, status = Rush::Status.success)
    klass = Class.new(Rush::AST::Node) do
      define_method(:execute) do |_executor|
        events << :body
        status
      end
    end
    klass.new
  end

  def between_entries?(events, selected)
    first = events.index(:enter)
    last = events.rindex(:enter)
    selected.map { |event| events.index(event) }.all? { |index| index && index > first && index < last }
  end

  it 'enters a subshell before the body and runs EXIT after the resolved status' do
    events = []
    trace(events, executor, :enter_subshell, :enter)
    trace(events, executor, :run, :run)
    trace(events, executor.trap_runner, :run_exit_trap, :exit)

    status = Rush::SubshellRunner.new(executor, node(events, Rush::Status.new(4))).run_body

    expect([events, status.exitstatus]).to eq([%i[enter run body exit], 4])
  end

  it 'closes stage pipes, arms the stop relay and binds IO before subshell entry' do
    events = []
    stage = Rush::PipelineRunner::Stage.new(0, [], 1)
    control = executor.jobs.control
    control.engage(nil)
    trace(events, stage, :close_unused, :close)
    trace(events, control, :arm_stage_relay, :arm)
    trace(events, executor, :with_io, :bind)
    trace(events, executor, :enter_subshell, :enter)

    status = Rush::PipelineRunner.new(executor, [node(events)]).send(:run_stage, stage)

    expect([events, status.exitstatus, control.relay?]).to eq([%i[close arm bind enter body], 0, true])
  end

  it 'snapshots monitor before entry, then isolates and re-enters before a background body' do
    events = []
    control = executor.job_control
    allow(executor).to receive(:job_control).and_return(control)
    trace(events, control, :monitored?, :monitor)
    trace(events, executor, :enter_subshell, :enter)
    allow(system).to receive(:trap_signal).and_wrap_original do |original, name, command, &block|
      events << :"ignore_#{name.downcase}"
      original.call(name, command, &block)
    end
    trace(events, system, :open_file, :stdin)

    status = Rush::BackgroundRunner.new(executor, node(events)).run_body

    setup = between_entries?(events, %i[ignore_int ignore_quit stdin])
    expect([events.take(2), setup, events.last(2), status.exitstatus])
      .to eq([%i[monitor enter], true, %i[enter body], 0])
  end

  it 'snapshots monitored mode before both entries without unmonitored isolation' do
    events = []
    executor.job_control.enable(system.stderr)
    control = executor.job_control
    allow(executor).to receive(:job_control).and_return(control)
    trace(events, control, :monitored?, :monitor)
    trace(events, executor, :enter_subshell, :enter)

    status = Rush::BackgroundRunner.new(executor, node(events)).run_body

    ignores = system.traps_installed.select { |name, command| %w[INT QUIT].include?(name) && command == 'IGNORE' }
    expect([events, status.exitstatus, executor.io.get(0), ignores])
      .to eq([%i[monitor enter enter body], 0, system.stdin, []])
  end

  it 'binds command-substitution stdout before entry and forces an untested body before EXIT' do
    events = []
    trace(events, executor, :with_io, :bind)
    trace(events, executor, :enter_subshell, :enter)
    trace(events, executor.errexit, :untested, :untested)
    trace(events, executor.trap_runner, :run_exit_trap, :exit)

    status = Rush::Expansion::CommandSubstitution.new(executor, 'true').capture(StringIO.new)

    expect(events.first(3)).to eq(%i[bind enter untested])
    expect([events.last, status.exitstatus]).to eq([:exit, 0])
  end

  it 'keeps immediate repeated subshell entry idempotent before child code starts' do
    executor.trap_runner.set(Rush::Signals::EXIT, 'echo outer')
    executor.trap_runner.set('TERM', 'echo term')
    executor.trap_runner.set('INT', '')
    executor.jobs.record(9)

    executor.enter_subshell
    snapshot = [state.traps.listing, system.traps_installed.dup,
                executor.jobs.ordered.map { |job| [job.pid, job.inherited?] }, executor.jobs.control.root]
    executor.enter_subshell

    expect([state.traps.listing, system.traps_installed,
            executor.jobs.ordered.map { |job| [job.pid, job.inherited?] }, executor.jobs.control.root])
      .to eq(snapshot)
  end
end
