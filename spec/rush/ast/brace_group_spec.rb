# frozen_string_literal: true

RSpec.describe Rush::AST::BraceGroup do
  it 'runs its body in the current executor' do
    executor = instance_double(Rush::Executor)
    allow(executor).to receive(:run).with(:body).and_return(Rush::Status.new(2))
    expect(described_class.new(:body).execute(executor).exitstatus).to eq(2)
  end
end
