# frozen_string_literal: true

RSpec.describe Rush::AST::WordSegment do
  def seg(value, quoted)
    Rush::AST::LiteralSegment.new(value, quoted)
  end

  def param(name, op: nil)
    Rush::AST::ParamRef.new(name: name, op: op, arg: nil)
  end

  it 'requires subclasses to implement #expand' do
    expect { described_class.new('x', false).expand(:executor) }.to raise_error(NotImplementedError)
  end

  it 'defaults to no literal value, no splitting and no splat' do
    segment = described_class.new('x', false)
    expect(segment.literal_value).to be_nil
    expect(segment.splittable?).to be(false)
    expect(segment.splat?).to be(false)
  end

  it 'copies a segment with a new value while preserving class and quote state' do
    copy = seg('x', true).with_value('y')
    expect([copy.class, copy.value, copy.quoted]).to eq([Rush::AST::LiteralSegment, 'y', true])
  end

  it 'expands literal text to itself' do
    expect(seg('x', false).expand(:executor)).to eq('x')
  end

  it 'uses only unquoted literal text as a literal value' do
    expect(seg('x', false).literal_value).to eq('x')
    expect(seg('x', true).literal_value).to be_nil
  end

  it 'marks unquoted dynamic segments as splittable' do
    expect(Rush::AST::DynamicSegment.new('x', false)).to be_splittable
    expect(Rush::AST::DynamicSegment.new('x', true)).not_to be_splittable
  end

  it 'marks $@ and unquoted $* parameter segments as splats' do
    expect(Rush::AST::ParamSegment.new(param('@'), true)).to be_splat
    expect(Rush::AST::ParamSegment.new(param('*'), false)).to be_splat
  end

  it 'does not splat quoted $*, ordinary parameters, or operator forms' do
    expect(Rush::AST::ParamSegment.new(param('*'), true)).not_to be_splat
    expect(Rush::AST::ParamSegment.new(param('x'), false)).not_to be_splat
    expect(Rush::AST::ParamSegment.new(param('@', op: ':-'), false)).not_to be_splat
  end

  it 'expands parameter segments through the parameter expander' do
    executor = instance_double(Rush::Executor)
    ref = param('x')
    expander = instance_double(Rush::Expansion::ParameterExpander, expand: 'value')
    allow(Rush::Expansion::ParameterExpander).to receive(:new).with(executor, ref).and_return(expander)

    expect(Rush::AST::ParamSegment.new(ref, false).expand(executor)).to eq('value')
    expect(Rush::Expansion::ParameterExpander).to have_received(:new).with(executor, ref)
  end

  it 'expands command segments through command substitution' do
    executor = instance_double(Rush::Executor)
    expander = instance_double(Rush::Expansion::CommandSubstitution, expand: 'out')
    allow(Rush::Expansion::CommandSubstitution).to receive(:new).with(executor, 'echo hi').and_return(expander)

    expect(Rush::AST::CommandSegment.new('echo hi', false).expand(executor)).to eq('out')
    expect(Rush::Expansion::CommandSubstitution).to have_received(:new).with(executor, 'echo hi')
  end

  it 'expands arithmetic segments through the arithmetic expander' do
    executor = instance_double(Rush::Executor)
    expander = instance_double(Rush::Expansion::ArithmeticExpander, expand: '3')
    allow(Rush::Expansion::ArithmeticExpander).to receive(:new).with(executor, '1 + 2').and_return(expander)

    expect(Rush::AST::ArithSegment.new('1 + 2', false).expand(executor)).to eq('3')
    expect(Rush::Expansion::ArithmeticExpander).to have_received(:new).with(executor, '1 + 2')
  end

  it 'equals and eql?-s a distinct segment of the same class, value and quoted flag' do
    twin = seg('x', false)
    expect(seg('x', false)).to eq(twin)
    expect(seg('x', false)).to eql(twin)
  end

  it 'hashes equal for two equal segments and differs by class, value or quote state' do
    segment = seg('x', true)
    twin = seg('x', true)
    expect(segment.hash).to be_a(Integer)
    expect(segment.hash).to eq([Rush::AST::LiteralSegment, 'x', true].hash)
    expect(segment.hash).to eq(twin.hash)
    expect(segment.hash).not_to eq(Rush::AST::DynamicSegment.new('x', true).hash)
    expect(segment.hash).not_to eq(seg('y', true).hash)
    expect(segment.hash).not_to eq(seg('x', false).hash)
  end

  it 'differs on class, value or quoted flag' do
    base = seg('x', false)
    expect(base == Rush::AST::DynamicSegment.new('x', false)).to be(false)
    expect(base == seg('y', false)).to be(false)
    expect(base == seg('x', true)).to be(false)
  end
end
