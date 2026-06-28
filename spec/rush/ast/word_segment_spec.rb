# frozen_string_literal: true

RSpec.describe Rush::AST::WordSegment do
  def seg(value, quoted)
    Rush::AST::LiteralSegment.new(value, quoted)
  end

  it 'equals and eql?-s a distinct segment of the same class, value and quoted flag' do
    twin = seg('x', false)
    expect(seg('x', false)).to eq(twin)
    expect(seg('x', false)).to eql(twin)
  end

  it 'hashes equal for two equal segments' do
    twin = seg('x', true)
    expect(seg('x', true).hash).to eq(twin.hash)
  end

  it 'differs on class, value or quoted flag' do
    base = seg('x', false)
    expect(base).not_to eq(Rush::AST::DynamicSegment.new('x', false))
    expect(base).not_to eq(seg('y', false))
    expect(base).not_to eq(seg('x', true))
  end
end
