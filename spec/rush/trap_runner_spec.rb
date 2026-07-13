# frozen_string_literal: true

RSpec.describe Rush::TrapRunner do
  let(:system) { FakeSystemCalls.new }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new) }
  let(:runner) { executor.trap_runner }
  let(:base_int) { proc { :interrupted } }

  def install_base
    runner.install_base('INT' => base_int, 'TERM' => proc {})
  end

  it 'installs base handlers as blocks, not IGNORE, so exec resets them' do
    install_base
    expect(system.traps_installed).to eq([['INT', nil], ['TERM', nil]])
    expect(system.trap_block('INT').call).to eq(:interrupted)
  end

  it 'lets a trap action override a base handler' do
    install_base
    runner.set('INT', 'echo got')
    system.trap_block('INT').call
    expect(system.stdout.string).to eq("got\n")
  end

  it 'restores the base handler, not the OS default, when a trap is reset' do
    install_base
    runner.set('INT', 'echo got')
    runner.reset('INT')
    expect(system.trap_block('INT').call).to eq(:interrupted)
  end

  it 'resets to the OS default for signals without a base handler' do
    runner.set('HUP', 'echo got')
    runner.reset('HUP')
    expect(system.traps_installed.last).to eq(%w[HUP SYSTEM_DEFAULT])
  end

  it 'drops base handlers to the OS default for a subshell' do
    install_base
    runner.reset_caught_for_subshell
    expect(system.traps_installed.last(2)).to eq([%w[INT SYSTEM_DEFAULT], %w[TERM SYSTEM_DEFAULT]])
  end

  it 'resets only the caught traps for a subshell, keeping the ignored ones' do
    runner.set('HUP', 'echo got')
    runner.set('USR1', '')
    runner.reset_caught_for_subshell
    expect([executor.state.traps.action('HUP'), executor.state.traps.action('USR1')]).to eq([nil, ''])
  end

  it 'clears the recorded action on reset' do
    runner.set('HUP', 'echo got')
    runner.reset('HUP')
    expect(executor.state.traps.action('HUP')).to be_nil
  end

  it 'installs IGNORE for an empty action string' do
    runner.set('USR2', '')
    expect(system.traps_installed).to eq([%w[USR2 IGNORE]])
  end

  it 'keeps the table entry when the OS refuses the disposition (KILL, like dash)' do
    runner.set('KILL', 'echo x')
    expect(executor.state.traps.action('KILL')).to eq('echo x')
  end

  it 'never installs an OS disposition for the EXIT pseudo-signal' do
    runner.set(Rush::Signals::EXIT, 'echo bye')
    expect(system.traps_installed).to be_empty
  end

  it 'preserves $? across a delivered signal action (POSIX 2.14)' do
    runner.set('USR1', 'true')
    executor.state.record_status(Rush::Status.new(7))
    system.trap_block('USR1').call
    expect(executor.state.last_status.exitstatus).to eq(7)
  end

  it 'does nothing when the action was cleared under a live handler' do
    runner.set('USR1', 'echo got')
    executor.state.traps.clear('USR1')
    expect { system.trap_block('USR1').call }.not_to raise_error
    expect(system.stdout.string).to eq('')
  end

  it 'parses the action with the shell aliases visible (dash-verified)' do
    executor.state.aliases.define('greet', 'echo hi')
    runner.set('USR1', 'greet')
    system.trap_block('USR1').call
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'swallows a broken trap action without killing the shell' do
    runner.set('USR1', 'if')
    expect { system.trap_block('USR1').call }.not_to raise_error
  end

  describe '#run_exit_trap' do
    it 'returns the code untouched when no EXIT trap is set' do
      expect(runner.run_exit_trap(3)).to eq(3)
    end

    it 'runs the EXIT action with $? published as the terminating code' do
      runner.set(Rush::Signals::EXIT, 'echo rc=$?')
      expect(runner.run_exit_trap(7)).to eq(7)
      expect(system.stdout.string).to eq("rc=7\n")
    end

    it 'lets an explicit exit inside the action override the exit code' do
      runner.set(Rush::Signals::EXIT, 'exit 9')
      expect(runner.run_exit_trap(3)).to eq(9)
    end

    it 'lets a bare exit in the action report the terminating status' do
      runner.set(Rush::Signals::EXIT, 'exit')
      expect(runner.run_exit_trap(5)).to eq(5)
    end

    it 'bare exit reports the terminating status even after the action changed $?' do
      runner.set(Rush::Signals::EXIT, 'false; exit')
      expect(runner.run_exit_trap(5)).to eq(5)
    end

    it 'clears the exiting status once the action has run' do
      runner.set(Rush::Signals::EXIT, 'true')
      runner.run_exit_trap(5)
      expect(runner.exiting_status).to eq(0)
    end

    it 'runs the EXIT action at most once' do
      runner.set(Rush::Signals::EXIT, 'echo once')
      expect([runner.run_exit_trap(3), runner.run_exit_trap(4)]).to eq([3, 4])
      expect(system.stdout.string).to eq("once\n")
    end

    it 'starts a fresh EXIT lifecycle after entering a subshell' do
      runner.set(Rush::Signals::EXIT, 'echo outer')
      runner.run_exit_trap(0)
      runner.reset_caught_for_subshell
      runner.set(Rush::Signals::EXIT, 'echo inner')
      expect(runner.run_exit_trap(0)).to eq(0)
      expect(system.stdout.string).to eq("outer\ninner\n")
    end

    it 'reports a fatal builtin error once and exits with status 2' do
      runner.set(Rush::Signals::EXIT, 'echo X; shift')
      expect([runner.run_exit_trap(0), runner.run_exit_trap(2)]).to eq([2, 2])
      expect([system.stdout.string, system.stderr.string]).to eq(["X\n", "rush: shift: can't shift that many\n"])
    end

    {
      'readonly assignment' => ['readonly x=1; x=2', 'rush: x: is read only'],
      'expansion failure' => ['set -u; echo $missing', 'rush: missing: parameter not set']
    }.each do |description, (action, diagnostic)|
      it "maps #{description} in the action to status 2" do
        runner.set(Rush::Signals::EXIT, action)
        expect(runner.run_exit_trap(0)).to eq(2)
        expect(system.stderr.string).to include(diagnostic)
      end
    end
  end

  describe '#exiting_status' do
    it 'falls back to the last command status when the shell is not exiting' do
      executor.state.record_status(Rush::Status.new(4))
      expect(runner.exiting_status).to eq(4)
    end
  end
end
