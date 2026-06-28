# frozen_string_literal: true

RSpec.describe Rush::AST::Subshell do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def body(source)
    Rush::Parser.new(Rush::Lexer.new(source)).parse
  end

  it 'runs the body in a forked subshell and adopts the child status' do
    system.wait_status = FakeSystemCalls::ChildStatus.new(5)
    expect(described_class.new(body('true')).execute(executor).exitstatus).to eq(5)
  end
end
