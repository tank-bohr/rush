# frozen_string_literal: true

RSpec.describe Rush::JobControl do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:control) { executor.job_control }

  describe '#enable / #disable' do
    it 'turns monitor on: the option appears and SIGTSTP gains an ignoring base disposition' do
      control.enable(system.stderr)
      expect(state.options.on?(:monitor)).to be(true)
      expect(system.traps_installed.last).to eq(['TSTP', nil])
    end

    it 'turns monitor off: the option drops and TSTP/TTOU return to the OS default (dash: both setsignals)' do
      control.enable(system.stderr)
      control.disable
      expect(state.options.on?(:monitor)).to be(false)
      expect(system.traps_installed.last(2)).to eq([%w[TSTP SYSTEM_DEFAULT], %w[TTOU SYSTEM_DEFAULT]])
    end

    it 'leaves a user TSTP trap in place when monitor flips on (dash: trap wins in either order)' do
      executor.trap_runner.set('TSTP', 'echo got')
      installed = system.traps_installed.size
      control.enable(system.stderr)
      expect(system.traps_installed.size).to eq(installed)
    end

    it 'leaves a user TSTP trap in place when monitor flips off' do
      control.enable(system.stderr)
      executor.trap_runner.set('TSTP', 'echo got')
      installed = system.traps_installed.count { |name, _command| name == 'TSTP' }
      control.disable
      expect(system.traps_installed.count { |name, _command| name == 'TSTP' }).to eq(installed)
    end

    it 'refuses in an interactive shell without a tty, like dash, leaving the flag off' do
      state.set_option(:interactive, true)
      control.enable(system.stderr)
      expect(state.options.on?(:monitor)).to be(false)
      expect(system.stderr.string).to include("can't access tty; job control turned off")
    end

    it 'turns on in an interactive shell that has a tty' do
      tty_system = FakeSystemCalls.new(tty: true)
      tty_executor = Rush::Executor.new(system: tty_system, state: state)
      state.set_option(:interactive, true)
      tty_executor.job_control.enable(tty_system.stderr)
      expect(state.options.on?(:monitor)).to be(true)
    end

    it 'refuses on a platform without process groups (the rush-mv8 gate)' do
      system.job_control_supported = false
      control.enable(system.stderr)
      expect(state.options.on?(:monitor)).to be(false)
      expect(system.stderr.string).to include('job control not supported')
    end

    it 'leaves TTOU alone without a terminal (dash-probed: off-tty TTOU still stops the shell)' do
      control.enable(system.stderr)
      expect(system.traps_installed.map(&:first)).not_to include('TTOU')
    end
  end

  # Plain memoized helpers (not let) keep the group under the memoized-helper
  # lint budget: the on-a-tty rig sits beside the outer off-tty one.
  def tty_system
    @tty_system ||= FakeSystemCalls.new(tty: true)
  end

  def tty_executor
    @tty_executor ||= Rush::Executor.new(system: tty_system, state: state)
  end

  def tty_control
    tty_executor.job_control
  end

  describe 'terminal acquisition (dash setjobctl)' do
    it 'self-leaders and takes the terminal whenever the tty is reachable, interactive or not' do
      tty_control.enable(tty_system.stderr)
      expect(tty_system.pgids_set).to eq([[0, 0]])
      expect(tty_system.handovers).to eq([4242])
      expect(tty_executor.jobs.control.terminal).to be_a(Rush::Terminal)
      expect(tty_system.stderr.string).to eq('')
    end

    it 'ignores TSTP and TTOU as base dispositions with the terminal in hand (dash-probed trio: TTIN stays)' do
      tty_control.enable(tty_system.stderr)
      expect(tty_system.traps_installed).to include(['TSTP', nil], ['TTOU', nil])
      expect(tty_system.traps_installed.map(&:first)).not_to include('TTIN')
    end

    it 'stops itself with SIGTTIN until a job-control parent brings it to the foreground' do
      tty_system.provide_tty_foreground(9999)
      tty_control.enable(tty_system.stderr)
      expect(tty_system.kills).to eq([['TTIN', 0]])
      expect(state.options.on?(:monitor)).to be(true)
    end

    it 'treats an unreadable foreground group as no tty at all: interactive refusal, handle closed' do
      state.set_option(:interactive, true)
      tty_system.provide_tty_foreground(nil)
      tty_control.enable(tty_system.stderr)
      expect(state.options.on?(:monitor)).to be(false)
      expect(tty_system.stderr.string).to include("can't access tty")
      expect(tty_system.open_tty).to be_closed
    end

    it 're-enabling while on is a no-op preserving the acquired terminal (dash: on == jobctl)' do
      tty_control.enable(tty_system.stderr)
      terminal = tty_executor.jobs.control.terminal
      tty_control.enable(tty_system.stderr)
      expect(tty_executor.jobs.control.terminal).to be(terminal)
      expect(tty_system.handovers).to eq([4242])
    end

    it 'set +m gives the terminal back to its acquisition-time owner, rejoins it and detaches' do
      tty_control.enable(tty_system.stderr)
      tty_control.disable
      expect(tty_system.handovers).to eq([4242, 4242])
      expect(tty_system.pgids_set).to eq([[0, 0], [0, 4242]])
      expect(tty_executor.jobs.control.terminal).to be_nil
      expect(tty_system.open_tty).to be_closed
    end

    it 'set +m returns TSTP and TTOU to the OS default' do
      tty_control.enable(tty_system.stderr)
      tty_control.disable
      expect(tty_system.traps_installed.last(2)).to eq([%w[TSTP SYSTEM_DEFAULT], %w[TTOU SYSTEM_DEFAULT]])
    end

    it 'acquires the terminal at startup when invocation-time -m finds a tty' do
      state.set_option(:monitor, true)
      tty_control.startup
      expect(tty_executor.jobs.control.terminal).to be_a(Rush::Terminal)
    end
  end

  describe '#foreground (terminal handover around a wait)' do
    it 'gives the terminal to the job group for the wait and reclaims it after' do
      tty_control.enable(tty_system.stderr)
      seen = nil
      tty_control.foreground([77]) do
        seen = tty_system.handovers.dup
        Rush::Status.success
      end
      expect(seen).to eq([4242, 77])
      expect(tty_system.handovers).to eq([4242, 77, 4242])
    end

    it 'reclaims the terminal even when the wait is interrupted' do
      tty_control.enable(tty_system.stderr)
      expect { tty_control.foreground([77]) { raise Rush::Interrupted, 'interrupted' } }
        .to raise_error(Rush::Interrupted)
      expect(tty_system.handovers.last).to eq(4242)
    end

    it 'runs the wait bare without a held terminal' do
      control.enable(system.stderr)
      expect(control.foreground([77]) { Rush::Status.new(3) }.exitstatus).to eq(3)
      expect(system.handovers).to be_empty
    end

    it 'runs the wait bare for a fake fork pid of 0' do
      tty_control.enable(tty_system.stderr)
      tty_control.foreground([0]) { Rush::Status.success }
      expect(tty_system.handovers).to eq([4242])
    end

    it 'parks a stopped foreground job in the table on the way out (^Z)' do
      tty_control.enable(tty_system.stderr)
      status = tty_control.foreground([77, 78]) { Rush::Status.stopped(20) }
      job = tty_executor.jobs.current
      expect(status.exitstatus).to eq(148)
      expect([job&.pid, job&.members, job&.stopped?]).to eq([77, [77, 78], true])
    end
  end

  describe '#startup (invocation-time -m)' do
    it 'carries a non-interactive -m into the SIGTSTP base disposition' do
      state.set_option(:monitor, true)
      control.startup
      expect(state.options.on?(:monitor)).to be(true)
      expect(system.traps_installed.last).to eq(['TSTP', nil])
    end

    it 'drops -m in an interactive shell without a tty (dash warns at startup)' do
      state.set_option(:monitor, true)
      state.set_option(:interactive, true)
      control.startup
      expect(state.options.on?(:monitor)).to be(false)
    end

    it 'does nothing without -m' do
      control.startup
      expect(system.traps_installed).to be_empty
    end
  end

  describe '#monitored?' do
    it 'is off by default' do
      expect(control.monitored?).to be(false)
    end

    it 'is on in the root shell with monitor set' do
      control.enable(system.stderr)
      expect(control.monitored?).to be(true)
    end

    it 'switches off for a forked child environment while $- keeps m (dash: root shell only)' do
      control.enable(system.stderr)
      executor.enter_subshell
      expect([control.monitored?, state.options.on?(:monitor)]).to eq([false, true])
    end

    it 'stays off when a subshell itself sets -m (dash-probed: flag only, no machinery)' do
      executor.enter_subshell
      control.enable(system.stderr)
      expect([control.monitored?, state.options.on?(:monitor)]).to eq([false, true])
    end
  end

  describe '#launch' do
    it 'forks without touching process groups while monitor is off' do
      allow(system).to receive(:fork).and_return(50)
      expect(control.launch { nil }).to eq(50)
      expect(system.pgids_set).to be_empty
    end

    it 'makes the child its own group leader under monitor (parent side of double setpgid)' do
      control.enable(system.stderr)
      allow(system).to receive(:fork).and_return(50)
      control.launch { nil }
      expect(system.pgids_set).to eq([[50, 0]])
    end

    it 'joins the child to an existing leader group under monitor' do
      control.enable(system.stderr)
      allow(system).to receive(:fork).and_return(51)
      control.launch(leader: 50) { nil }
      expect(system.pgids_set).to eq([[51, 50]])
    end

    it 'treats a non-positive leader as none (fake fork ports report pid 0)' do
      control.enable(system.stderr)
      allow(system).to receive(:fork).and_return(51)
      control.launch(leader: 0) { nil }
      expect(system.pgids_set).to eq([[51, 0]])
    end

    it 'skips grouping entirely when fork reports no child pid' do
      control.enable(system.stderr)
      expect(control.launch { nil }).to eq(0)
      expect(system.pgids_set).to be_empty
    end

    it 'hands the terminal to a foreground leader child only (dash forkchild FORK_FG)' do
      tty_control.enable(tty_system.stderr)
      allow(tty_system).to receive(:fork).and_return(50, 51, 52)
      tty_control.launch { nil }
      tty_control.launch(leader: 50) { nil }
      tty_control.launch_background { nil }
      expect(tty_system.tty_leaders).to eq([50])
    end

    it 'forks leaders without the terminal when the shell holds none' do
      control.enable(system.stderr)
      allow(system).to receive(:fork).and_return(50)
      control.launch { nil }
      expect(system.tty_leaders).to be_empty
    end
  end
end
