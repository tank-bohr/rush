# frozen_string_literal: true

RSpec.describe Rush::JobSpec do
  let(:system) { FakeSystemCalls.new }
  let(:table) { Rush::JobTable.new(system) }

  def resolve(spec)
    described_class.resolve(table, spec)
  end

  it 'resolves %, %% and %+ to the current job' do
    table.record(11)
    table.record(12)
    expect(['%', '%%', '%+'].map { |spec| resolve(spec).pid }).to eq([12, 12, 12])
  end

  it 'resolves %- to the previous job' do
    table.record(11)
    table.record(12)
    expect(resolve('%-').pid).to eq(11)
  end

  it 'resolves %n by job number' do
    table.record(11)
    expect(resolve('%1').pid).to eq(11)
  end

  it 'reads leading-zero numbers as decimal' do
    (1..8).each { |offset| table.record(offset + 100) }
    expect(resolve('%08').pid).to eq(108)
  end

  it 'reads two-digit numbers as decimal' do
    (1..10).each { |offset| table.record(offset + 100) }
    expect(resolve('%10').pid).to eq(110)
  end

  it 'reports No current job with an empty table' do
    expect { resolve('%%') }.to raise_error(Rush::JobError, 'No current job')
  end

  it 'reports No previous job with a single job' do
    table.record(11)
    expect { resolve('%-') }.to raise_error(Rush::JobError, 'No previous job')
  end

  it 'reports No such job for an unknown number' do
    expect { resolve('%7') }.to raise_error(Rush::JobError, 'No such job: %7')
  end

  it 'reports No such job for string forms (no command text off a tty)' do
    table.record(11)
    expect { resolve('%sle') }.to raise_error(Rush::JobError, 'No such job: %sle')
    expect { resolve('%?le') }.to raise_error(Rush::JobError, 'No such job: %?le')
  end

  it 'reports No such job for the empty spec' do
    table.record(11)
    expect { resolve('') }.to raise_error(Rush::JobError, 'No such job: ')
  end
end
