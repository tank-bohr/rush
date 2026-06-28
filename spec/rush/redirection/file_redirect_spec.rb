# frozen_string_literal: true

RSpec.describe Rush::Redirection::FileRedirect do
  let(:system) { FakeSystemCalls.new }
  let(:io) { Rush::IoTable.standard(system) }

  def redirect(io_number)
    Rush::AST::Redirect.new(kind: :out, target: nil, io_number: io_number)
  end

  it 'opens the target and binds it to the default fd' do
    result = described_class.new('w', 1).apply(redirect(nil), '/f', io, system)
    expect(result.get(1)).to be(system.files['/f'])
  end

  it 'binds to an explicit io_number when present' do
    result = described_class.new('w', 1).apply(redirect(2), '/f', io, system)
    expect(result.get(2)).to be(system.files['/f'])
  end

  it 'raises a redirect error when the target cannot be opened' do
    allow(system).to receive(:open_file).and_raise(Errno::ENOENT)
    expect { described_class.new('w', 1).apply(redirect(nil), '/no/such/f', io, system) }
      .to raise_error(Rush::RedirectError)
  end
end
