# frozen_string_literal: true

RSpec.describe Rush::Builtins::Unalias do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['unalias', *args], io).call
  def aliases = state.aliases

  before do
    aliases.define('a', '1')
    aliases.define('b', '2')
  end

  it 'removes a named alias' do
    run('a')
    expect([aliases.key?('a'), aliases.key?('b')]).to eq([false, true])
  end

  it 'removes several names' do
    run('a', 'b')
    expect([aliases.key?('a'), aliases.key?('b')]).to eq([false, false])
  end

  it 'removes everything with -a' do
    run('-a')
    expect(aliases.listing).to eq([])
  end

  it 'reports an unknown name on stderr with status 1' do
    status = run('gone')
    expect([status.exitstatus, system.stderr.string]).to eq([1, "unalias: gone not found\n"])
  end

  it 'keeps removing after a miss and ends with status 1' do
    status = run('a', 'gone', 'b')
    expect([status.exitstatus, aliases.listing]).to eq([1, []])
  end

  it 'succeeds with no operands' do
    expect(run.exitstatus).to eq(0)
  end

  it 'succeeds removing an alias whose value is empty' do
    aliases.define('e', '')
    expect(run('e').exitstatus).to eq(0)
  end
end
