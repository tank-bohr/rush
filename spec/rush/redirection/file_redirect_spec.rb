# frozen_string_literal: true

RSpec.describe Rush::Redirection::FileRedirect do
  let(:system) { FakeSystemCalls.new }
  let(:io) { Rush::IoTable.standard(system) }

  def redirect(io_number)
    Rush::AST::Redirect.new(kind: :out, target: nil, io_number: io_number)
  end

  it 'opens the target and binds it to the default fd' do
    result = described_class.new('w', 1).apply(redirect(nil), '/f', io, system)
    expect([result.get(1), result.entry(1).owned?]).to eq([system.files.fetch('/f'), true])
  end

  it 'binds to an explicit io_number when present' do
    result = described_class.new('w', 1).apply(redirect(2), '/f', io, system)
    expect([result.get(2), result.entry(2).owned?]).to eq([system.files.fetch('/f'), true])
  end

  it 'uses exclusive-create mode for protected redirects under noclobber' do
    options = Rush::Options.new
    options.set(:noclobber, true)
    allow(system).to receive(:open_file).and_call_original
    described_class.new('w', 1, options: options, protection: :noclobber).apply(redirect(nil), '/f', io, system)
    expect(system).to have_received(:open_file).with('/f', File::WRONLY | File::CREAT | File::EXCL)
  end

  it 'leaves explicit clobber redirects in truncating mode under noclobber' do
    options = Rush::Options.new
    options.set(:noclobber, true)
    allow(system).to receive(:open_file).and_call_original
    described_class.new('w', 1, options: options).apply(redirect(nil), '/f', io, system)
    expect(system).to have_received(:open_file).with('/f', 'w')
  end

  it 'uses ordinary truncating mode when no options object is attached' do
    allow(system).to receive(:open_file).and_call_original
    described_class.new('w', 1, protection: :noclobber).apply(redirect(nil), '/f', io, system)
    expect(system).to have_received(:open_file).with('/f', 'w')
  end

  it 'raises a redirect error when the target cannot be opened' do
    allow(system).to receive(:open_file).and_raise(Errno::ENOENT)
    expect { described_class.new('w', 1).apply(redirect(nil), '/no/such/f', io, system) }
      .to raise_error(Rush::RedirectError)
  end
end
