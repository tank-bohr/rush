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
end
