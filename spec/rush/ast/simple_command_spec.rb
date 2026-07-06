# frozen_string_literal: true

RSpec.describe Rush::AST::SimpleCommand do
  it 'stores assignments, words, redirects and source line' do
    assignments = [:assignment]
    words = [:word]
    redirects = [:redirect]
    command = described_class.new(assignments, words, redirects, source_line: 7)

    expect([command.assignments, command.words, command.redirects, command.source_line])
      .to eq([assignments, words, redirects, 7])
  end

  it 'builds from parsed source-order parts with the earliest source line' do
    first = Rush::AST::Word.literal('echo', source_line: 3)
    second = Rush::AST::Word.literal('hi', source_line: 4)
    command = described_class.from_parts([second, first])
    expect([command.words, command.source_line]).to eq([[second, first], 3])
  end

  it 'records LINENO and delegates execution to the command runner entry point' do
    state = instance_double(Rush::ShellState)
    executor = instance_double(Rush::Executor, state: state)
    command = described_class.new([], [], [], source_line: 5)
    allow(state).to receive(:record_lineno).with(5)
    allow(executor).to receive(:run_simple).with(command).and_return(Rush::Status.success)

    expect(command.execute(executor)).to be_success
    expect(state).to have_received(:record_lineno).with(5)
    expect(executor).to have_received(:run_simple).with(command)
  end
end
