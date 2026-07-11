# frozen_string_literal: true

RSpec.describe Rush::AST::Case do
  let(:system) { FakeSystemCalls.new }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new(environment: Rush::Environment.new({}))) }

  def word(text)
    Rush::AST::Word.literal(text)
  end

  def item(patterns, body)
    Rush::AST::CaseItem.new(patterns: patterns.map { |p| word(p) }, body: body)
  end

  it 'runs the body of the first matching arm' do
    allow(executor).to receive(:run).with(:body_a).and_return(Rush::Status.new(3))
    node = described_class.new(word('apple'), [item(['a*'], :body_a), item(['b*'], :body_b)])
    expect(node.execute(executor).exitstatus).to eq(3)
  end

  it 'yields success when no arm matches' do
    node = described_class.new(word('zzz'), [item(['a*'], :body_a)])
    expect(node.execute(executor)).to be_success
  end

  it 'matches on any of an arm alternation patterns' do
    allow(executor).to receive(:run).with(:body).and_return(Rush::Status.success)
    described_class.new(word('y'), [item(%w[x y z], :body)]).execute(executor)
    expect(executor).to have_received(:run).with(:body)
  end

  it 'matches a POSIX character class' do
    allow(executor).to receive(:run).with(:body).and_return(Rush::Status.success)
    described_class.new(word('a'), [item(['[[:alpha:]]'], :body)]).execute(executor)
    expect(executor).to have_received(:run).with(:body)
  end

  it 'keeps a quoted character class literal' do
    allow(executor).to receive(:run)
    quoted = Rush::AST::Word.new([Rush::AST::LiteralSegment.new('[[:alpha:]]', true)])
    node = described_class.new(word('a'), [Rush::AST::CaseItem.new(patterns: [quoted], body: :body)])

    expect(node.execute(executor)).to be_success
    expect(executor).not_to have_received(:run)
  end
end
