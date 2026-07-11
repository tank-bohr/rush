# frozen_string_literal: true

RSpec.describe Rush::Terminal do
  let(:system) { FakeSystemCalls.new(tty: true) }
  let(:tty) { system.open_tty }
  let(:terminal) { described_class.new(system: system, tty: tty, home: 4242, initial: 4000) }

  it 'hands the terminal to a job process group' do
    terminal.give(77)
    expect(system.handovers).to eq([77])
  end

  it 'reclaims the terminal to the shell own group' do
    terminal.give(77)
    terminal.reclaim
    expect(system.handovers).to eq([77, 4242])
  end

  it 'restores the acquisition-time owner, rejoins that group and releases the handle (set +m)' do
    terminal.restore
    expect(system.handovers).to eq([4000])
    expect(system.pgids_set).to eq([[0, 4000]])
    expect(tty).to be_closed
  end

  describe '.acquire (dash setjobctl)' do
    it 'answers nil without a reachable tty' do
      expect(described_class.acquire(FakeSystemCalls.new)).to be_nil
    end

    it 'self-leaders, takes the tty and remembers the initial owner' do
      acquired = described_class.acquire(system)
      expect(acquired).to be_a(described_class)
      expect(system.pgids_set).to eq([[0, 0]])
      expect(system.handovers).to eq([4242])
    end

    it 'waits for the foreground with SIGTTIN while another group owns the tty' do
      system.provide_tty_foreground(9999)
      described_class.acquire(system)
      expect(system.kills).to eq([['TTIN', 0]])
    end

    it 'closes the handle and answers nil when the foreground group is unreadable' do
      system.provide_tty_foreground(nil)
      expect(described_class.acquire(system)).to be_nil
      expect(system.open_tty).to be_closed
      expect(system.pgids_set).to be_empty
    end
  end

  describe '.while_held' do
    it 'runs the wait bare without a terminal' do
      called = false
      described_class.while_held(nil, 77) { called = true }
      expect(called).to be(true)
      expect(system.handovers).to be_empty
    end

    it 'runs the wait bare for a non-positive leader' do
      described_class.while_held(terminal, 0) { :ok }
      expect(system.handovers).to be_empty
    end

    it 'gives for the block and reclaims after' do
      seen = nil
      described_class.while_held(terminal, 77) { seen = system.handovers.dup }
      expect(seen).to eq([77])
      expect(system.handovers).to eq([77, 4242])
    end

    it 'reclaims even when the wait raises' do
      expect { described_class.while_held(terminal, 77) { raise Rush::Interrupted, 'x' } }
        .to raise_error(Rush::Interrupted)
      expect(system.handovers).to eq([77, 4242])
    end

    it 'answers the block value' do
      expect(described_class.while_held(terminal, 77) { 42 }).to eq(42)
    end
  end
end
