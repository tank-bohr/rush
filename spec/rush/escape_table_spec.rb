# frozen_string_literal: true

RSpec.describe Rush::EscapeTable do
  let(:table) { { 'n' => "\n" } }

  it 'renders a known escape through the table' do
    expect(described_class.render('n', table)).to eq("\n")
  end

  it 'keeps the backslash for an unknown escape' do
    expect(described_class.render('z', table)).to eq('\\z')
  end

  it 'renders a missing trailing character as a literal backslash' do
    expect(described_class.render(nil, table)).to eq('\\')
  end
end
