# frozen_string_literal: true

RSpec.describe Rush::Expansion::GlobExpander do
  def glob(field, globs: {}, noglob: false)
    state = Rush::ShellState.new
    state.options.set(:noglob, true) if noglob
    executor = Rush::Executor.new(system: FakeSystemCalls.new(globs: globs), state: state)
    described_class.new(executor).expand(field)
  end

  it 'returns the matches for a pattern that matches files' do
    expect(glob('*.txt', globs: { '*.txt' => %w[a.txt b.txt] })).to eq(%w[a.txt b.txt])
  end

  it 'returns the literal field with escapes removed when nothing matches' do
    expect(glob('\\*.md')).to eq(['*.md'])
  end

  it 'skips globbing and only unescapes while noglob is set' do
    expect(glob('\\[x\\]', globs: { '\\[x\\]' => ['z'] }, noglob: true)).to eq(['[x]'])
  end
end
