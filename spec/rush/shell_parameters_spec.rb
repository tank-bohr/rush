# frozen_string_literal: true

RSpec.describe Rush::ShellParameters do
  let(:state) do
    Rush::ShellState.new(environment: Rush::Environment.new('V' => 'v'), name: 'sh', positional: %w[a b c],
                         shell_pid: 4242)
  end
  let(:parameters) { state.parameters }

  before { state.record_status(Rush::Status.new(3)) }

  it 'resolves ordinary variables' do
    expect(parameters.resolve('V')).to eq('v')
  end

  it 'resolves special parameters' do
    resolved = %w[? # $ 0 @ *].map { |name| parameters.resolve(name) }
    expect(resolved).to eq(['3', '3', '4242', 'sh', 'a b c', 'a b c'])
  end

  it 'resolves positional parameters by index' do
    resolved = [parameters.resolve('2'), parameters.resolve('9')]
    expect(resolved).to eq(['b', nil])
  end

  it 'returns placeholders for special parameters without current values' do
    expect([parameters.resolve('-'), parameters.resolve('!')]).to eq(['', nil])
  end

  it 'resolves $!' do
    state.record_background_pid(1234)
    expect(parameters.resolve('!')).to eq('1234')
  end

  it 'joins $* with the first IFS character' do
    state.variables.assign('IFS', ':-')
    expect(parameters.resolve('*')).to eq('a:b:c')
  end

  it 'joins $* with no separator when IFS is null' do
    state.variables.assign('IFS', '')
    expect(parameters.resolve('*')).to eq('abc')
  end
end
