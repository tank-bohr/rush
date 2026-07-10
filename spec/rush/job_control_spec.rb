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

    it 'turns monitor off: the option drops and SIGTSTP returns to the OS default' do
      control.enable(system.stderr)
      control.disable
      expect(state.options.on?(:monitor)).to be(false)
      expect(system.traps_installed.last).to eq(%w[TSTP SYSTEM_DEFAULT])
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
      installed = system.traps_installed.size
      control.disable
      expect(system.traps_installed.size).to eq(installed)
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
  end
end
