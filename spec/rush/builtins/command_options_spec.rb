# frozen_string_literal: true

RSpec.describe Rush::Builtins::CommandOptions do
  it 'parses clustered option letters ahead of the operands' do
    opts = described_class.new(%w[-pv name arg])
    expect([opts.default_path?, opts.verify?, opts.verbose?, opts.operands])
      .to eq([true, true, false, %w[name arg]])
  end

  it 'accumulates separate clusters, repeats included' do
    opts = described_class.new(%w[-p -p -V x])
    expect([opts.default_path?, opts.verbose?, opts.verify?, opts.name]).to eq([true, true, false, 'x'])
  end

  it 'stops at --, a lone dash, a +cluster or the first operand (dash-probed)' do
    expect(described_class.new(%w[-- -v x]).operands).to eq(%w[-v x])
    expect(described_class.new(%w[- x]).operands).to eq(%w[- x])
    expect(described_class.new(%w[+v x]).operands).to eq(%w[+v x])
    expect(described_class.new(%w[name -v]).operands).to eq(%w[name -v])
  end

  it 'records the first unknown letter as illegal, keeping earlier flags' do
    expect(described_class.new(%w[-pz echo]).illegal).to eq('-z')
    expect(described_class.new(%w[-v echo]).illegal).to be_nil
    expect(described_class.new(%w[-pz echo])).to be_default_path
  end

  it 'answers a nil name when no operands remain' do
    opts = described_class.new(%w[-v])
    expect([opts.name, opts.operands, opts.verify?]).to eq([nil, [], true])
  end
end
