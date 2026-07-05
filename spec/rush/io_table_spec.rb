# frozen_string_literal: true

RSpec.describe Rush::IoTable do
  let(:system) { FakeSystemCalls.new }

  it 'builds a standard table from borrowed system streams' do
    table = described_class.standard(system)
    expect([table.get(0), table.get(1), table.get(2)])
      .to eq([system.stdin, system.stdout, system.stderr])
    expect(table.entries).to all(satisfy { |entry| !entry.owned? && !entry.closed? })
  end

  it 'wraps raw initializer streams as borrowed entries' do
    table = described_class.new(1 => :sink)
    expect([table.get(1), table.entry(1).owned?]).to eq([:sink, false])
  end

  it 'returns nil for an unopened fd' do
    expect(described_class.standard(system).get(9)).to be_nil
  end

  it 'binds a borrowed fd without mutating the original' do
    table = described_class.standard(system)
    redirected = table.with(1, :sink)
    expect([redirected.get(1), redirected.entry(1).owned?, table.get(1)])
      .to eq([:sink, false, system.stdout])
  end

  it 'binds an owned fd' do
    table = described_class.standard(system)
    redirected = table.with_owned(1, :sink)
    expect([redirected.get(1), redirected.entry(1).owned?]).to eq([:sink, true])
  end

  it 'binds a closed fd' do
    table = described_class.standard(system).with_closed(2)
    expect(table.entry(2)).to be_closed
    expect { table.get(2) }.to raise_error(Errno::EBADF)
  end

  it 'exposes stream spawn options' do
    table = described_class.standard(system).with(1, :sink)
    expect(table.to_spawn_options).to include(1 => :sink)
  end

  it 'maps a closed entry to :close in spawn options' do
    table = described_class.standard(system).with_closed(2)
    expect(table.to_spawn_options.fetch(2)).to eq(:close)
  end

  it 'closes only newly owned entries over the base table' do
    base = described_class.standard(system).with_owned(4, :persistent)
    table = base.with_owned(1, :fresh).with(3, :borrowed)
    allow(system).to receive(:close_redirect)
    table.close_opened_over(base, system)
    expect(system).to have_received(:close_redirect).with(:fresh)
    expect(system).not_to have_received(:close_redirect).with(:persistent)
    expect(system).not_to have_received(:close_redirect).with(:borrowed)
  end
end
