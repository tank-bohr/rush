# frozen_string_literal: true

RSpec.describe Rush::AST::FunctionDef do
  it 'registers the body in the function table and succeeds' do
    state = Rush::ShellState.new
    executor = Rush::Executor.new(system: FakeSystemCalls.new, state: state)
    expect(described_class.new('f', :body).execute(executor)).to be_success
    expect(state.functions.fetch('f')).to eq(:body)
  end
end
