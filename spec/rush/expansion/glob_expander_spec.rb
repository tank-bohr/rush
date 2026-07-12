# frozen_string_literal: true

RSpec.describe Rush::Expansion::GlobExpander do
  def glob(text, noglob: false, system: nil, quoted: false)
    state = Rush::ShellState.new
    state.options.set(:noglob, true) if noglob
    calls = system || FakeSystemCalls.new
    executor = Rush::Executor.new(system: calls, state: state)
    field = Rush::Expansion::IfsScanner::Field.new
    field.append(text, quoted)
    [].tap { |expanded| described_class.new(executor).append(field, expanded) }
  end

  it 'returns the matches for wildcard and bracket patterns' do
    globs = { '*.txt' => %w[a.txt b.txt], '?at' => ['cat'], '[ab]' => %w[a b],
              '[[:digit:]]' => ['7'], '[x\\]]' => [']'], '\\\\*' => ['\\one'] }
    system = FakeSystemCalls.new(globs: globs)
    allow(system).to receive(:glob).and_call_original

    expect(glob('*.txt', system: system)).to eq(%w[a.txt b.txt])
    expect(glob('?at', system: system)).to eq(['cat'])
    expect(glob('[ab]', system: system)).to eq(%w[a b])
    expect(glob('[[:digit:]]', system: system)).to eq(['7'])
    expect(glob('[x\\]]', system: system)).to eq([']'])
    expect(glob('\\\\*', system: system)).to eq(['\\one'])
    expect(system).to have_received(:glob).exactly(6).times
  end

  it 'bypasses globbing for literal, slash, empty, quoted, and unclosed fields' do
    system = FakeSystemCalls.new
    allow(system).to receive(:glob).and_call_original

    fields = ['plain', 'dir/file', '', '[unfinished', ']!^-', 'é']
    expect(fields.map { |field| glob(field, system: system) })
      .to eq([['plain'], ['dir/file'], [''], ['[unfinished'], [']!^-'], ['é']])
    expect(glob('*', quoted: true, system: system)).to eq(['*'])
    expect(glob('[x]', quoted: true, system: system)).to eq(['[x]'])
    expect(system).not_to have_received(:glob)
  end

  it 'preserves data backslashes, including one that quotes a wildcard' do
    system = FakeSystemCalls.new
    allow(system).to receive(:glob).and_call_original

    expect(glob('\\q', system: system)).to eq(['\\q'])
    expect(glob('\\*', system: system)).to eq(['\\*'])
    expect(glob('\\[x]', system: system)).to eq(['\\[x]'])
    expect(system).not_to have_received(:glob)
  end

  it 'calls glob for an unmatched pattern before falling back to the literal field' do
    system = FakeSystemCalls.new
    allow(system).to receive(:glob).and_call_original
    expect(glob('missing*', system: system)).to eq(['missing*'])
    expect(system).to have_received(:glob).with('missing*', locale: instance_of(Array))
  end

  it 'skips globbing and returns literal text while noglob is set' do
    system = FakeSystemCalls.new(globs: { '\\[x\\]' => ['z'] })
    allow(system).to receive(:glob).and_call_original
    expect(glob('[x]', quoted: true, noglob: true, system: system)).to eq(['[x]'])
    expect(system).not_to have_received(:glob)
  end
end
