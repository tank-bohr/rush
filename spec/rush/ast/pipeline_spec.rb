# frozen_string_literal: true

RSpec.describe Rush::AST::Pipeline do
  it 'runs its single command and returns that status' do
    executor = instance_double(Rush::Executor)
    allow(executor).to receive(:run).with(:cmd).and_return(Rush::Status.new(5))
    expect(described_class.new([:cmd]).execute(executor).exitstatus).to eq(5)
  end
end
