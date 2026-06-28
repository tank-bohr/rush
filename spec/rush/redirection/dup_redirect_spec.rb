# frozen_string_literal: true

RSpec.describe Rush::Redirection::DupRedirect do
  let(:system) { FakeSystemCalls.new }
  let(:io) { Rush::IoTable.standard(system) }

  def redirect(io_number) = Rush::AST::Redirect.new(kind: :dup_out, target: nil, io_number: io_number)

  it 'duplicates the source fd onto the default fd (>&2)' do
    result = described_class.new(1).apply(redirect(nil), '2', io, system)
    expect(result.get(1)).to be(io.get(2))
  end

  it 'duplicates onto an explicit io_number (2>&1)' do
    result = described_class.new(1).apply(redirect(2), '1', io, system)
    expect(result.get(2)).to be(io.get(1))
  end

  it 'binds a closed stream for a - target (n>&-)' do
    result = described_class.new(1).apply(redirect(nil), '-', io, system)
    expect(result.get(1)).to be_a(Rush::ClosedStream)
  end

  it 'raises a RedirectError when the source fd is not open' do
    expect { described_class.new(1).apply(redirect(nil), '9', io, system) }.to raise_error(Rush::RedirectError)
  end

  it 'raises a RedirectError when the source fd was already closed' do
    closed = io.with(2, Rush::ClosedStream.new)
    expect { described_class.new(1).apply(redirect(nil), '2', closed, system) }.to raise_error(Rush::RedirectError)
  end

  it 'raises a BuiltinError for a non-numeric target' do
    expect { described_class.new(1).apply(redirect(nil), 'foo', io, system) }.to raise_error(Rush::BuiltinError)
  end
end
