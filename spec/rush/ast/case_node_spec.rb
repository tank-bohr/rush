# frozen_string_literal: true

RSpec.describe Rush::AST::Case do
  let(:system) { FakeSystemCalls.new }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new(environment: Rush::Environment.new({}))) }

  def word(text) = Rush::AST::Word.literal(text)
  def item(patterns, body) = Rush::AST::CaseItem.new(patterns: patterns.map { |p| word(p) }, body: body)

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
end
