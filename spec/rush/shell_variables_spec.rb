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
end
