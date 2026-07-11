# frozen_string_literal: true

RSpec.describe Rush::JobReport do
  let(:system) { FakeSystemCalls.new }
  let(:table) { Rush::JobTable.new(system) }

  def job(pid = 50)
    table.record(pid)
    table.ordered.find { |entry| entry.pid == pid }
  end

  it 'renders the showjob line: number, mark, state, text starting at column 34' do
    entry = job
    expect(described_class.line(table, entry)).to eq('[1] + Running'.ljust(33))
  end

  it 'inserts the pid field between the mark and the state (jobs -l)' do
    entry = job(50)
    expect(described_class.line(table, entry, '50 ')).to eq('[1] + 50 Running'.ljust(33))
  end

  describe '.state (dash statusfmt vocabulary)' do
    subject(:entry) { Rush::JobTable::Job.new(1, 50) }

    it 'says Running while nothing was reaped' do
      expect(described_class.state(entry)).to eq('Running')
    end

    it 'spells every Stopped flavour by signal' do
      states = [20, 19, 21, 22].map do |sig|
        entry.stop(sig)
        described_class.state(entry)
      end
      expect(states).to eq(['Stopped', 'Stopped (signal)', 'Stopped (tty input)', 'Stopped (tty output)'])
    end

    it 'says Done for a clean exit and Done(n) for a code' do
      entry.finish(FakeSystemCalls::ChildStatus.new(0, nil))
      expect(described_class.state(entry)).to eq('Done')
      entry.finish(FakeSystemCalls::ChildStatus.new(5, nil))
      expect(described_class.state(entry)).to eq('Done(5)')
    end

    it 'describes the killing signal' do
      entry.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
      expect(described_class.state(entry)).to eq('Killed')
      entry.finish(FakeSystemCalls::ChildStatus.new(nil, 15))
      expect(described_class.state(entry)).to eq('Terminated')
    end
  end
end
