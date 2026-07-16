# frozen_string_literal: true

RSpec.describe Rush::Signals do
  it 'decodes a numeric spec through the signal table' do
    expect(described_class.decode('2')).to eq('INT')
  end

  it 'decodes 0 as the EXIT pseudo-signal' do
    expect(described_class.decode('0')).to eq('EXIT')
  end

  it 'decodes names case-insensitively without a SIG prefix' do
    expect([described_class.decode('int'), described_class.decode('Term')]).to eq(%w[INT TERM])
  end

  it 'rejects a SIG-prefixed name' do
    expect(described_class.decode('SIGINT')).to be_nil
  end

  it 'rejects an out-of-range number' do
    expect(described_class.decode('99')).to be_nil
  end

  it 'rejects an unknown name' do
    expect(described_class.decode('NOPE')).to be_nil
  end

  it 'maps a canonical name back to its signal number' do
    expect(described_class.number('TERM')).to eq(15)
  end

  it 'describes the common signals like strsignal, as the jobs listing prints them' do
    expect([described_class.description(9), described_class.description(15)])
      .to eq(%w[Killed Terminated])
  end

  it 'spells the glibc strsignal descriptions printsignal reports (rush-hkp)' do
    expect([10, 12, 7, 5].map { |number| described_class.description(number) })
      .to eq(['User defined signal 1', 'User defined signal 2', 'Bus error', 'Trace/breakpoint trap'])
  end

  it 'falls back to the signal name, then to Signal N' do
    expect([described_class.description(17), described_class.description(99)])
      .to eq(['CHLD', 'Signal 99'])
  end

  it 'labels each stop signal as the jobs listing shows it, defaulting to Stopped' do
    expect([19, 20, 21, 22, 99].map { |number| described_class.stop_description(number) })
      .to eq(['Stopped (signal)', 'Stopped', 'Stopped (tty input)', 'Stopped (tty output)', 'Stopped'])
  end
end
