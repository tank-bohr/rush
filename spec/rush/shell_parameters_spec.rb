# frozen_string_literal: true

RSpec.describe Rush::ShellParameters do
  let(:state) do
    Rush::ShellState.new(environment: Rush::Environment.new('V' => 'v'), name: 'sh', positional: %w[a b c],
                         pids: Rush::ShellProcessIds.new(4242, 3131))
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

  it 'renders $- flags in the dash order, so the oracle comparison holds' do
    %i[allexport noclobber errexit nounset xtrace noglob verbose].each { |name| state.options.set(name, true) }
    expect(parameters.resolve('-')).to eq('uaCvxfe')
  end

  it 'includes the invocation-only stdin and interactive flags in $-' do
    state.options.set(:stdin, true)
    state.options.set(:interactive, true)
    expect(parameters.resolve('-')).to eq('si')
  end

  it 'gives pipefail no $- letter, like dash' do
    state.options.set(:pipefail, true)
    expect(parameters.resolve('-')).to eq('')
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
