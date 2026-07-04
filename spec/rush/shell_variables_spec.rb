# frozen_string_literal: true

RSpec.describe Rush::ShellVariables do
  let(:environment) { Rush::Environment.new('x' => 'global') }
  let(:variables) { described_class.new(environment) }

  it 'delegates ordinary variable reads and writes to the environment' do
    variables.assign('name', 'value')
    expect(variables.get('name')).to eq('value')
  end

  it 'applies and exports declaration operands' do
    variables.export_operand('A=1')
    expect(variables.exported).to include('A' => '1')
  end

  it 'applies and marks readonly declaration operands' do
    variables.readonly_operand('A=1')
    expect { variables.assign('A', '2') }.to raise_error(Rush::ReadonlyError)
  end

  it 'snapshots a local declaration before applying its assignment' do
    variables.begin_scope
    variables.declare_local_operand('x=local')
    variables.end_scope
    expect(variables.get('x')).to eq('global')
  end
end
