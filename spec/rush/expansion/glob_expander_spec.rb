# frozen_string_literal: true

RSpec.describe Rush::Expansion::GlobExpander do
  def glob(field, globs: {}, noglob: false, system: nil)
    state = Rush::ShellState.new
    state.options.set(:noglob, true) if noglob
    calls = system || FakeSystemCalls.new(globs: globs)
    executor = Rush::Executor.new(system: calls, state: state)
    described_class.new(executor).expand(field)
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

  it 'bypasses globbing for literal, slash, empty, and escaped fields' do
    system = FakeSystemCalls.new
    allow(system).to receive(:glob).and_call_original

    fields = ['plain', 'dir/file', '', '\\*', '\\?', '\\[x\\]', '[x\\]', '[unfinished', ']!^-', 'é']
    expect(fields.map { |field| glob(field, system: system) })
      .to eq([['plain'], ['dir/file'], [''], ['*'], ['?'], ['[x]'], ['[x]'], ['[unfinished'], [']!^-'], ['é']])
    expect(system).not_to have_received(:glob)
  end

  it 'calls glob for an unmatched pattern before falling back to the literal field' do
    system = FakeSystemCalls.new
    allow(system).to receive(:glob).and_call_original
    expect(glob('missing*', system: system)).to eq(['missing*'])
    expect(system).to have_received(:glob).with('missing*', locale: instance_of(Array))
  end

  it 'skips globbing and only unescapes while noglob is set' do
    system = FakeSystemCalls.new(globs: { '\\[x\\]' => ['z'] })
    allow(system).to receive(:glob).and_call_original
    expect(glob('\\[x\\]', noglob: true, system: system)).to eq(['[x]'])
    expect(system).not_to have_received(:glob)
  end
end
