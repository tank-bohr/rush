# frozen_string_literal: true

RSpec.describe Rush::Executor do
  let(:state) { Rush::ShellState.new }

  def build(**extra) = described_class.new(system: FakeSystemCalls.new, state: state, **extra)

  it 'defaults the builtin registry' do
    expect(build.builtins.key?('echo')).to be(true)
  end

  it 'records the last status when running a node' do
    build.run(Rush::AST::SimpleCommand.new([Rush::AST::Word.literal('false')]))
    expect(state.last_status.exitstatus).to eq(1)
  end

  it 'accepts an injected builtin registry' do
    registry = Rush::Builtins::Registry.new
    expect(build(builtins: registry).builtins).to be(registry)
  end
end
