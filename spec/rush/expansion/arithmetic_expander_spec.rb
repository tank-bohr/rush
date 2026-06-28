# frozen_string_literal: true

RSpec.describe Rush::Expansion::ArithmeticExpander do
  let(:env) { Rush::Environment.new('y' => '5') }
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new(environment: env)) }

  def expand(source)
    described_class.new(executor, source).expand
  end

  it 'returns the evaluated expression as a string' do
    expect(expand('2 + 3 * 4')).to eq('14')
  end

  it 'parameter-expands the text before evaluating it' do
    expect(expand('$y + 1')).to eq('6')
  end

  it 'evaluates a bare name without a leading dollar' do
    expect(expand('y * 2')).to eq('10')
  end
end
