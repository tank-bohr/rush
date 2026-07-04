# frozen_string_literal: true

RSpec.describe Rush::EscapeTable do
  let(:table) { { 'n' => "\n" } }
  let(:escapes) { described_class.new(table) }

  it 'renders a known escape through the table' do
    expect(escapes.escape('n')).to eq("\n")
  end

  it 'keeps the backslash for an unknown escape' do
    expect(escapes.escape('z')).to eq('\\z')
  end

  it 'renders a missing trailing character as a literal backslash' do
    expect(escapes.escape(nil)).to eq('\\')
  end
end
