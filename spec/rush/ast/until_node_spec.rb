# frozen_string_literal: true

RSpec.describe Rush::AST::Until do
  it 'runs through an until LoopRunner' do
    executor = instance_double(Rush::Executor)
    runner = instance_double(Rush::LoopRunner, call: Rush::Status.new(0))
    allow(Rush::LoopRunner).to receive(:new).with(executor, :cond, :body, :until).and_return(runner)
    expect(described_class.new(:cond, :body).execute(executor)).to be_success
  end
end
