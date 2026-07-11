# frozen_string_literal: true

RSpec.describe Rush::StopRelay do
  let(:system) { FakeSystemCalls.new }
  let(:control) { Rush::JobTable::Control.new }

  def stopped(sig)
    FakeSystemCalls::ChildStatus.new(nil, nil, sig)
  end

  describe '.relay?' do
    it 'fires only when the relay is armed AND the status is a stop' do
      expect(described_class.relay?(control, stopped(20))).to be(false)
      control.engage(nil)
      control.arm_stage_relay
      expect(described_class.relay?(control, stopped(20))).to be(true)
      expect(described_class.relay?(control, FakeSystemCalls::ChildStatus.new(0, nil))).to be(false)
    end
  end

  describe '.raise_onto_self' do
    it 'restores the default disposition, then re-raises the stop signal onto this process' do
      described_class.raise_onto_self(system, stopped(20))
      expect(system.traps_installed).to eq([%w[TSTP SYSTEM_DEFAULT]])
      expect(system.kills).to eq([['TSTP', 4242]])
    end

    it 'skips the untrappable STOP disposition but still re-raises the stop' do
      described_class.raise_onto_self(system, stopped(19))
      expect([system.traps_installed, system.kills]).to eq([[], [['STOP', 4242]]])
    end
  end
end
