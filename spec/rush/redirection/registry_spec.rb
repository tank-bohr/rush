# frozen_string_literal: true

RSpec.describe Rush::Redirection::Registry do
  it 'registers and fetches appliers' do
    registry = described_class.new
    registry.register(:out, :applier)
    expect(registry.fetch(:out)).to eq(:applier)
  end

  it 'provides a default applier for every file redirection kind' do
    registry = Rush::Redirection.default_registry
    kinds = %i[in out append readwrite clobber]
    expect(kinds.map { |kind| registry.fetch(kind) }).to all(be_a(Rush::Redirection::FileRedirect))
  end

  it 'wires the read-side kinds to their modes on fd 0' do
    system = FakeSystemCalls.new
    allow(system).to receive(:open_file).and_call_original
    registry = Rush::Redirection.default_registry

    { in: 'r', readwrite: File::RDWR | File::CREAT }.each do |kind, mode|
      result = registry.fetch(kind).apply(ast_redirect(kind), "/#{kind}", Rush::IoTable.standard(system), system)
      expect(system).to have_received(:open_file).with("/#{kind}", mode)
      expect(result.entry(0).owned?).to be(true)
    end
  end

  it 'wires the write-side kinds to their modes on fd 1, only out noclobber-protected' do
    system = FakeSystemCalls.new
    allow(system).to receive(:open_file).and_call_original
    noclobber = Rush::Options.new.tap { |options| options.set(:noclobber, true) }
    registry = Rush::Redirection.default_registry(noclobber)

    { out: File::WRONLY | File::CREAT | File::EXCL, append: 'a', clobber: 'w' }.each do |kind, mode|
      result = registry.fetch(kind).apply(ast_redirect(kind), "/#{kind}", Rush::IoTable.standard(system), system)
      expect(system).to have_received(:open_file).with("/#{kind}", mode)
      expect(result.entry(1).owned?).to be(true)
    end
  end

  it 'wires dup_out to fd 1, dup_in to fd 0, and the here-document applier' do
    system = FakeSystemCalls.new
    io = Rush::IoTable.standard(system)
    registry = Rush::Redirection.default_registry

    expect(registry.fetch(:dup_out).apply(ast_redirect(:dup_out), '2', io, system).entry(1)).to be(io.entry(2))
    expect(registry.fetch(:dup_in).apply(ast_redirect(:dup_in), '1', io, system).entry(0)).to be(io.entry(1))
    expect(registry.fetch(:heredoc)).to be_a(Rush::Redirection::HereDocRedirect)
  end

  def ast_redirect(kind)
    Rush::AST::Redirect.new(kind: kind, target: nil, io_number: nil)
  end
end
