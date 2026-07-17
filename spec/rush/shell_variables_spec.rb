# frozen_string_literal: true

RSpec.describe Rush::ShellVariables do
  let(:environment) { Rush::Environment.new('x' => 'global') }
  let(:variables) { described_class.new(environment) }

  it 'delegates ordinary variable reads and writes to the environment' do
    variables.assign('name', 'value')
    expect(variables.get('name')).to eq('value')
  end

  it 'returns the assigned value' do
    expect(variables.assign('name', 'value')).to eq('value')
  end

  it 'resolves locale categories through LC_ALL, the category, LANG and C' do
    expect(variables.locale_settings).to eq(%w[C C])
    variables.assign('LANG', 'lang')
    variables.assign('LC_COLLATE', 'collate')
    expect(variables.locale_settings).to eq(%w[collate lang])
    variables.assign('LC_ALL', 'all')
    expect(variables.locale_settings).to eq(%w[all all])
    variables.assign('LC_ALL', '')
    expect(variables.locale_settings).to eq(%w[collate lang])
  end

  it 'starts with allexport off: a plain assign stays unexported' do
    variables.assign('N', '1')
    expect(variables.exported).not_to include('N' => '1')
  end

  it 'exports every assignment while allexport is on (set -a)' do
    variables.allexport = true
    variables.assign('N', '1')
    expect(variables.exported).to include('N' => '1')
  end

  it 'stops exporting once allexport turns off again' do
    variables.allexport = true
    variables.allexport = false
    variables.assign('N', '1')
    expect(variables.exported).not_to include('N' => '1')
  end

  it 'applies and exports declaration operands' do
    variables.export_operand('A=1')
    expect(variables.exported).to include('A' => '1')
  end

  it 'applies and marks readonly declaration operands' do
    variables.readonly_operand('A=1')
    expect { variables.assign('A', '2') }.to raise_error(Rush::ReadonlyError)
  end

  it 'applies the local assignment inside its scope' do
    variables.begin_scope
    variables.declare_local_operand('x=local')
    expect(variables.get('x')).to eq('local')
    variables.end_scope
  end

  it 'snapshots a local declaration before applying its assignment' do
    variables.begin_scope
    variables.declare_local_operand('x=local')
    variables.end_scope
    expect(variables.get('x')).to eq('global')
  end

  it 'forwards environment lifecycle operations with their results' do
    variables.assign('A', 'old')
    variables.export('A')
    temporary = variables.with_temporary('A' => 'temp') { [variables.get('A'), 42] }
    variables.update_lineno(7)
    variables.assign('B', 'gone')
    variables.unset('B')
    variables.readonly('A')

    expect([temporary, variables.get('A'), variables.get('B'), variables.get('LINENO'), variables.exported]).to eq(
      [['temp', 42], 'old', nil, '7', { 'x' => 'global', 'A' => 'old' }]
    )
    expect { variables.validate_assignment('A') }.to raise_error(Rush::ReadonlyError)
    variables.unset('missing')
  end

  it 'forwards logical-directory and function-scope operations' do
    variables.seed_pwd('/start')
    variables.move_to('/next')
    variables.begin_scope
    variables.declare_local('x')
    variables.assign('x', 'inner')

    expect([variables.pwd, variables.current_pwd, variables.in_function?]).to eq(['/next', '/next', true])
    variables.end_scope
    expect([variables.in_function?, variables.get('x')]).to eq([false, 'global'])
  end
end
