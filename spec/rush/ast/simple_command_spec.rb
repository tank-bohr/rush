# frozen_string_literal: true

RSpec.describe Rush::AST::SimpleCommand do
  it 'stores assignments, words and redirects' do
    assignments = [:assignment]
    words = [:word]
    redirects = [:redirect]
    command = described_class.new(assignments, words, redirects)

    expect([command.assignments, command.words, command.redirects]).to eq([assignments, words, redirects])
  end

  it 'delegates execution to the command runner entry point' do
    executor = instance_double(Rush::Executor)
    command = described_class.new([], [], [])
    allow(executor).to receive(:run_simple).with(command).and_return(Rush::Status.success)

    expect(command.execute(executor)).to be_success
    expect(executor).to have_received(:run_simple).with(command)
  end
end
