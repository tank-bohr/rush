# frozen_string_literal: true

RSpec.describe Rush::ClosedStream do
  subject(:stream) { described_class.new }

  it 'raises a bad-file-descriptor error on a read or write' do
    expect { stream.write('x') }.to raise_error(Errno::EBADF)
    expect { stream.gets }.to raise_error(Errno::EBADF)
  end

  it 'treats close as a no-op returning nil (it owns nothing)' do
    expect(stream.close).to be_nil
  end

  it 'treats flush as a no-op returning self' do
    expect(stream.flush).to be(stream)
  end
end
