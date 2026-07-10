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
end
