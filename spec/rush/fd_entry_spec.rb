# frozen_string_literal: true

RSpec.describe Rush::FdEntry do
  let(:system) { FakeSystemCalls.new }

  it 'wraps a borrowed stream without owning it' do
    stream = StringIO.new
    entry = described_class.borrowed(stream)
    expect([entry.stream, entry.owned?, entry.closed?, entry.to_spawn_option]).to eq([stream, false, false, stream])
  end

  it 'wraps an owned stream and closes it through the system port' do
    stream = StringIO.new
    entry = described_class.owned(stream)
    allow(system).to receive(:close_redirect)
    entry.close_redirect(system)
    expect(system).to have_received(:close_redirect).with(stream)
  end

  it 'does not close borrowed streams' do
    entry = described_class.borrowed(StringIO.new)
    allow(system).to receive(:close_redirect)
    entry.close_redirect(system)
    expect(system).not_to have_received(:close_redirect)
  end

  it 'models a closed fd entry' do
    entry = described_class.closed
    expect([entry.owned?, entry.closed?, entry.to_spawn_option]).to eq([false, true, :close])
    expect { entry.stream }.to raise_error(Errno::EBADF)
  end
end
