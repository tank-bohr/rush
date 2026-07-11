# frozen_string_literal: true

RSpec.describe Rush::Builtins::TestOperators do
  it 'knows the unary and binary primary names' do
    unaries = %w[-n -z -t -e -f -d -r -w -x -s -h -L -p -b -c -S -g -u]
    expect(unaries.map { |op| described_class.unary?(op) }).to all(be(true))
    expect(%w[= != -eq -ne -gt -ge -lt -le].map { |op| described_class.binary?(op) }).to all(be(true))
    expect([described_class.unary?('-a'), described_class.binary?('-o')]).to all(be(false))
  end

  it 'dispatches string and integer binary primaries' do
    expect(described_class.apply_binary('=', 'a', 'a')).to be(true)
    expect(described_class.apply_binary('-lt', ' 3', '10 ')).to be(true)
  end

  it 'raises TestError for a non-integer numeric operand' do
    expect { described_class.apply_binary('-eq', 'x', '1') }
      .to raise_error(Rush::TestError, 'x: integer expected')
  end

  it 'parses -t descriptor numbers with the atomax strictness of dash' do
    expect(described_class.fd_number(' +07 ')).to eq(7)
    expect { described_class.fd_number('2x') }.to raise_error(Rush::TestError, 'Illegal number: 2x')
  end
end
