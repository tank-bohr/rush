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
end
