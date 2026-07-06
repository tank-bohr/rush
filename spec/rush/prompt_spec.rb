# frozen_string_literal: true

RSpec.describe Rush::Prompt do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:prompt) { described_class.new(executor) }

  it 'defaults to the POSIX prompts' do
    expect([prompt.primary, prompt.continuation]).to eq(['$ ', '> '])
  end

  it 'defaults the primary prompt to # for a privileged shell' do
    root = Rush::Executor.new(system: FakeSystemCalls.new(privileged: true), state: state)
    expect(described_class.new(root).primary).to eq('# ')
  end

  it 'reads the prompts from the PS1/PS2 shell variables' do
    state.variables.assign('PS1', 'mine> ')
    state.variables.assign('PS2', 'more> ')
    expect([prompt.primary, prompt.continuation]).to eq(['mine> ', 'more> '])
  end

  it 're-reads the variable at every prompt' do
    state.variables.assign('PS1', 'one> ')
    first = prompt.primary
    state.variables.assign('PS1', 'two> ')
    expect([first, prompt.primary]).to eq(['one> ', 'two> '])
  end

  it 'subjects the value to parameter expansion' do
    state.record_status(Rush::Status.new(3))
    state.variables.assign('PS1', '[$?]$ ')
    expect(prompt.primary).to eq('[3]$ ')
  end

  it 'expands the braced parameter forms' do
    state.variables.assign('PS1', '${site:-local}> ')
    expect(prompt.primary).to eq('local> ')
  end

  it 'leaves command substitution, backticks and backslashes literal' do
    state.variables.assign('PS1', '$(echo X) `echo Y` \\w ')
    expect(prompt.primary).to eq('$(echo X) `echo Y` \\w ')
  end

  it 'keeps a dollar that begins no reference literal' do
    state.variables.assign('PS1', '100$ ')
    expect(prompt.primary).to eq('100$ ')
  end

  it 'falls back to the raw value on an unterminated ${' do
    state.variables.assign('PS1', '${oops ')
    expect(prompt.primary).to eq('${oops ')
  end

  it 'falls back to the raw value when a ${x?} form fails' do
    state.variables.assign('PS1', '${unset?boom}> ')
    expect(prompt.primary).to eq('${unset?boom}> ')
  end
end
