# frozen_string_literal: true

RSpec.describe Rush::PendingSignals do
  subject(:pending) { described_class.new }

  it 'coalesces repeats and drains distinct signals in number order' do
    pending.record('USR2')
    pending.record('USR2')
    pending.record('USR1')
    drained = []
    pending.drain { |name| drained << name }
    expect([drained, pending.any?]).to eq([%w[USR1 USR2], false])
  end

  it 'keeps draining a signal recorded from inside a delivery' do
    drained = []
    pending.record('USR1')
    pending.drain do |name|
      drained << name
      pending.record('USR2') if name == 'USR1'
    end
    expect(drained).to eq(%w[USR1 USR2])
  end

  it 'detaches a batch without clearing a signal recorded into the replacement' do
    pending.record('USR1')
    batch = pending.__send__(:take)
    pending.record('USR2')
    expect([batch, pending.first]).to eq([['USR1'], 'USR2'])
  end

  it 'reports the next signal and clears the set' do
    pending.record('TERM')
    expect([pending.first, pending.any?]).to eq(['TERM', true])
    pending.clear
    expect([pending.first, pending.any?]).to eq([nil, false])
  end
end
