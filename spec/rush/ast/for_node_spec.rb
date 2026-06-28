# frozen_string_literal: true

RSpec.describe Rush::AST::For do
  let(:executor) { instance_double(Rush::Executor) }
  let(:runner) { instance_double(Rush::ForRunner, call: Rush::Status.success) }

  it 'expands an explicit word list and iterates over the fields' do
    expander = instance_double(Rush::Expansion::Pipeline, expand: %w[a b])
    allow(executor).to receive(:expander).and_return(expander)
    allow(Rush::ForRunner).to receive(:new).with(executor, 'x', %w[a b], :body).and_return(runner)
    expect(described_class.new('x', [:word], :body).execute(executor)).to be_success
  end

  it 'iterates over the positional parameters when there is no in clause' do
    state = Rush::ShellState.new
    state.replace_positional(%w[p q])
    allow(executor).to receive(:state).and_return(state)
    allow(Rush::ForRunner).to receive(:new).with(executor, 'x', %w[p q], :body).and_return(runner)
    expect(described_class.new('x', nil, :body).execute(executor)).to be_success
  end
end
