# frozen_string_literal: true

RSpec.describe Rush::Builtins::Echo do
  let(:system) { FakeSystemCalls.new }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new) }

  def echo(*args) = described_class.new(executor, ['echo', *args]).call

  it 'joins arguments with spaces and appends a newline' do
    expect(echo('a', 'b')).to be_success
    expect(system.stdout.string).to eq("a b\n")
  end

  it 'suppresses the trailing newline with -n' do
    echo('-n', 'x')
    expect(system.stdout.string).to eq('x')
  end

  it 'prints just a newline when given no operands' do
    echo
    expect(system.stdout.string).to eq("\n")
  end
end
