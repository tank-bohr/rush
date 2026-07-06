# frozen_string_literal: true

RSpec.describe Rush::Expansion::Resolver do
  subject(:resolver) { described_class.new(executor) }

  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new('V' => 'v'), name: 'sh', shell_pid: 4242) }
  let(:executor) { instance_double(Rush::Executor, state: state) }

  before do
    state.record_status(Rush::Status.new(3))
    state.positional.replace(%w[a b c])
  end

  it 'resolves ordinary variables' do
    expect(resolver.resolve('V')).to eq('v')
  end

  it 'resolves the special parameters' do
    specials = %w[? # $ 0 @ *].map { |name| resolver.resolve(name) }
    expect(specials).to eq(['3', '3', '4242', 'sh', 'a b c', 'a b c'])
  end

  it 'resolves positional parameters by index' do
    expect([resolver.resolve('2'), resolver.resolve('9')]).to eq(['b', nil])
  end

  it 'returns placeholders for the deferred special parameters' do
    expect([resolver.resolve('-'), resolver.resolve('!')]).to eq(['', nil])
  end

  it 'joins $* with the first IFS character' do
    state.variables.assign('IFS', ':-')
    expect(resolver.resolve('*')).to eq('a:b:c')
  end

  it 'joins $* with no separator when IFS is null' do
    state.variables.assign('IFS', '')
    expect(resolver.resolve('*')).to eq('abc')
  end
end
