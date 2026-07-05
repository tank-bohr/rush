# frozen_string_literal: true

RSpec.describe Rush::Redirection::DupRedirect do
  let(:system) { FakeSystemCalls.new }
  let(:io) { Rush::IoTable.standard(system) }

  def redirect(io_number)
    Rush::AST::Redirect.new(kind: :dup_out, target: nil, io_number: io_number)
  end

  it 'duplicates the source fd entry onto the default fd (>&2)' do
    result = described_class.new(1).apply(redirect(nil), '2', io, system)
    expect(result.entry(1)).to be(io.entry(2))
    expect(result.get(1)).to be(io.get(2))
  end

  it 'duplicates onto an explicit io_number (2>&1)' do
    result = described_class.new(1).apply(redirect(2), '1', io, system)
    expect(result.entry(2)).to be(io.entry(1))
    expect(result.get(2)).to be(io.get(1))
  end

  it 'binds a closed entry for a - target (n>&-)' do
    result = described_class.new(1).apply(redirect(nil), '-', io, system)
    expect(result.entry(1)).to be_closed
    expect { result.get(1) }.to raise_error(Errno::EBADF)
  end

  it 'falls back to a parent-inherited fd absent from the io table' do
    inherited = StringIO.new
    system.inherit_fd(9, inherited)
    result = described_class.new(1).apply(redirect(nil), '9', io, system)
    expect([result.get(1), result.entry(1).owned?]).to eq([inherited, false])
  end

  it 'raises a RedirectError when the source fd is not open' do
    expect { described_class.new(1).apply(redirect(nil), '9', io, system) }.to raise_error(Rush::RedirectError)
  end

  it 'raises a RedirectError when the source fd was already closed without falling back' do
    system.inherit_fd(2, StringIO.new)
    closed = io.with_closed(2)
    expect { described_class.new(1).apply(redirect(nil), '2', closed, system) }.to raise_error(Rush::RedirectError)
  end

  it 'raises a BuiltinError for a non-numeric target' do
    expect { described_class.new(1).apply(redirect(nil), 'foo', io, system) }.to raise_error(Rush::BuiltinError)
  end
end
