# frozen_string_literal: true

RSpec.describe Rush::IoTable do
  let(:system) { FakeSystemCalls.new }

  it 'builds a standard table from the system streams' do
    table = described_class.standard(system)
    expect([table.get(0), table.get(1), table.get(2)])
      .to eq([system.stdin, system.stdout, system.stderr])
  end

  it 'binds a new fd without mutating the original' do
    table = described_class.standard(system)
    redirected = table.with(1, :sink)
    expect(redirected.get(1)).to eq(:sink)
    expect(table.get(1)).to be(system.stdout)
  end

  it 'exposes its streams as spawn options' do
    table = described_class.standard(system).with(1, :sink)
    expect(table.to_spawn_options).to include(1 => :sink)
  end
end
