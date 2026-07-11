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

  # POSIX 2.5.3: unset PS4 takes the default. dash instead initializes PS4
  # as a set variable at startup, so an explicit `unset PS4` there leaves an
  # empty prefix; rush keeps its render-time-default treatment (as PS1/PS2).
  it 'defaults the trace prefix to the POSIX "+ "' do
    expect(prompt.trace).to eq('+ ')
  end

  it 'reads the trace prefix from the PS4 shell variable' do
    state.variables.assign('PS4', 'TR> ')
    expect(prompt.trace).to eq('TR> ')
  end

  it 'subjects PS4 to parameter expansion' do
    state.variables.assign('lvl', 'deep')
    state.variables.assign('PS4', '[${lvl}] ')
    expect(prompt.trace).to eq('[deep] ')
  end

  # Parameter expansion ONLY: a PS4 holding $(cmd), backticks or $((...))
  # stays literal, so tracing can never recurse into command execution.
  # dash executes NONE of them either — it strips backticks unexecuted,
  # errors $(cmd) back to the raw string, and expands only $((arith)); the
  # visible-prefix divergences (backticks, arith) side with POSIX 2.5.3's
  # parameter-expansion-only wording and are pinned here.
  it 'never executes command substitution or arithmetic from PS4' do
    state.variables.assign('PS4', '$(echo X)`echo Y`$((1+2)) ')
    expect(prompt.trace).to eq('$(echo X)`echo Y`$((1+2)) ')
  end

  # dash also falls back to the raw string on a failing ${x?} (per-line
  # diagnostic on stderr, rc 0, commands still run); rush's fallback is the
  # same minus the diagnostic — stderr sits outside the verification model.
  it 'falls back to the raw value when a PS4 ${x?} form fails' do
    state.variables.assign('PS4', '${unset?boom} ')
    expect(prompt.trace).to eq('${unset?boom} ')
  end

  # dash honors a backslash-dollar escape while expanding PS4; ParamText has
  # no escapes (a backslash is literal text, the parameter still expands) —
  # POSIX 2.5.3 is silent on escapes, PS1/PS2/ENV share the treatment, and
  # the divergence is adjudicated to the simpler shared model and pinned.
  it 'keeps a backslash literal and expands the parameter it precedes' do
    state.variables.assign('lvl', 'x')
    state.variables.assign('PS4', '\\$lvl ')
    expect(prompt.trace).to eq('\\x ')
  end
end
