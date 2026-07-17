# frozen_string_literal: true

RSpec.describe Rush::Positional do
  subject(:positional) { described_class.new(%w[first second]) }

  it 'reads indexed, sized, copied and joined positional values' do
    expect(positional.to_a).to eq(%w[first second])
    expect([positional[0], positional[2], positional.size, positional.join, positional.join(':')])
      .to eq(['first', nil, 2, 'firstsecond', 'first:second'])
  end
end
