# frozen_string_literal: true

RSpec.describe Rush::Positional do
  subject(:positional) { described_class.new(%w[first second]) }

  it 'reads indexed, sized, copied and joined positional values' do
    expect(positional.to_a).to eq(%w[first second])
    expect([positional[0], positional[2], positional.size, positional.join, positional.join(':')])
      .to eq(['first', nil, 2, 'firstsecond', 'first:second'])
  end

  it 'preserves the array-compatible comparison and enumerable reads' do
    expect([positional == %w[first second], positional.empty?, described_class.new.empty?, positional.map(&:upcase)])
      .to eq([true, false, true, %w[FIRST SECOND]])
    expect(positional.each.to_a).to eq(%w[first second])
    seen = []
    expect(positional.each { |value| seen << value }).to eq(%w[first second])
    expect(seen).to eq(%w[first second])
    expect(positional.map.each(&:upcase)).to eq(%w[FIRST SECOND])
  end
end
