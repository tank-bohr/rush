# frozen_string_literal: true

RSpec.describe Rush::ShellParameters do
  let(:variables) { Rush::ShellVariables.new(Rush::Environment.new('V' => 'v')) }
  let(:positional) { Rush::Positional.new(%w[a b c]) }
  let(:status) { Rush::Status.new(3) }
  let(:parameters) do
    described_class.new(variables: variables, positional: positional, name: 'sh', status: -> { status })
  end

  it 'resolves ordinary variables' do
    expect(parameters.resolve('V', pid: 4242)).to eq('v')
  end

  it 'resolves special parameters' do
    resolved = %w[? # $ 0 @ *].map { |name| parameters.resolve(name, pid: 4242) }
    expect(resolved).to eq(['3', '3', '4242', 'sh', 'a b c', 'a b c'])
  end

  it 'resolves positional parameters by index' do
    resolved = [parameters.resolve('2', pid: 4242), parameters.resolve('9', pid: 4242)]
    expect(resolved).to eq(['b', nil])
  end

  it 'returns placeholders for deferred special parameters' do
    expect([parameters.resolve('-', pid: 4242), parameters.resolve('!', pid: 4242)]).to eq(['', nil])
  end

  it 'joins $* with the first IFS character' do
    variables.assign('IFS', ':-')
    expect(parameters.resolve('*', pid: 4242)).to eq('a:b:c')
  end

  it 'joins $* with no separator when IFS is null' do
    variables.assign('IFS', '')
    expect(parameters.resolve('*', pid: 4242)).to eq('abc')
  end
end
