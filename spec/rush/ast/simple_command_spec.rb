# frozen_string_literal: true

RSpec.describe Rush::AST::SimpleCommand do
  it 'is born with canonical mixed source-order parts and the earliest source line' do
    assignment = Rush::AST::Assignment.new('X', Rush::AST::Word.literal('1', source_line: 3))
    word = Rush::AST::Word.literal('echo', source_line: 4)
    redirect = Rush::AST::Redirect.new(
      kind: :out, target: Rush::AST::Word.literal('out', source_line: 5), io_number: nil
    )
    parts = [redirect, assignment, word]
    command = described_class.new(parts)

    expect(command.parts).to be(parts)
    expect([command.parts, command.assignments, command.words, command.redirects, command.source_line])
      .to eq([parts, [assignment], [word], [redirect], 3])
  end

  it 'names grouped compatibility construction and its artificial group order explicitly' do
    assignments = [Rush::AST::Assignment.new('X', Rush::AST::Word.literal('1'))]
    words = [Rush::AST::Word.literal('echo')]
    redirects = [Rush::AST::Redirect.new(kind: :out, target: Rush::AST::Word.literal('out'), io_number: nil)]
    command = described_class.from_groups(assignments, words, redirects, source_line: 7)

    expect([command.parts, command.source_line]).to eq([assignments + words + redirects, 7])
  end

  it 'records LINENO and delegates execution to the command runner entry point' do
    state = instance_double(Rush::ShellState)
    executor = instance_double(Rush::Executor, state: state)
    command = described_class.new([], source_line: 5)
    allow(state).to receive(:record_lineno).with(5)
    allow(executor).to receive(:run_simple).with(command).and_return(Rush::Status.success)

    expect(command.execute(executor)).to be_success
    expect(state).to have_received(:record_lineno).with(5)
    expect(executor).to have_received(:run_simple).with(command)
  end
end
