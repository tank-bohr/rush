# frozen_string_literal: true

RSpec.describe Rush::Assignments do
  let(:variables) { Rush::ShellVariables.new(Rush::Environment.new('x' => 'global')) }
  let(:assignments) { described_class.new(variables) }

  it 'returns a bare name without materializing it as a variable' do
    expect(assignments.apply('NAME')).to eq('NAME')
    expect(variables.get('NAME')).to be_nil

    variables.export('NAME')
    expect(variables.exported).not_to include('NAME')
  end

  it 'assigns a value split at the first equals sign' do
    expect(assignments.apply('NAME=a=b')).to eq('NAME')
    expect(variables.get('NAME')).to eq('a=b')
  end

  it 'parses a bare name as a two-slot name/value pair' do
    expect(assignments.__send__(:parse, 'NAME')).to eq(['NAME', nil])
  end

  it 'keeps an explicit empty value distinct from a missing assignment' do
    assignments.apply('NAME=')
    expect(variables.get('NAME')).to eq('')
  end

  it 'declares a local name before assigning it' do
    variables.begin_scope
    expect(assignments.apply_local('x=local')).to eq('x')
    expect(variables.get('x')).to eq('local')
    variables.end_scope
    expect(variables.get('x')).to eq('global')
  end
end
