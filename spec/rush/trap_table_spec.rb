# frozen_string_literal: true

RSpec.describe Rush::TrapTable do
  subject(:traps) { described_class.new }

  it 'stores and reads an action by name' do
    traps.set('INT', 'echo hi')
    expect(traps.action('INT')).to eq('echo hi')
  end

  it 'clears an action, restoring the default' do
    traps.set('INT', 'x')
    traps.clear('INT')
    expect(traps.action('INT')).to be_nil
  end

  it 'lists actions ordered by signal number' do
    traps.set('TERM', 'a')
    traps.set('EXIT', 'b')
    traps.set('INT', 'c')
    expect(traps.listing).to eq([%w[EXIT b], %w[INT c], %w[TERM a]])
  end
end
