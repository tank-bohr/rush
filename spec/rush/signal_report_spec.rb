# frozen_string_literal: true

RSpec.describe Rush::SignalReport do
  let(:err) { StringIO.new }

  def killed(signal, coredump: false)
    Rush::Status.new(signal + 128, termsig: signal, coredump: coredump)
  end

  describe '.report' do
    it 'writes the strsignal description for a signal death and returns the status' do
      status = killed(15)
      expect(described_class.report(status, err)).to be(status)
      expect(err.string).to eq("Terminated\n")
    end

    it 'suffixes (core dumped) when the OS recorded a dump' do
      described_class.report(killed(11, coredump: true), err)
      expect(err.string).to eq("Segmentation fault (core dumped)\n")
    end

    it 'stays silent for SIGINT and SIGPIPE deaths (dash printsignal exclusions)' do
      described_class.report(killed(2), err)
      described_class.report(killed(13), err)
      expect(err.string).to be_empty
    end

    it 'stays silent for a plain exit and for a stop' do
      described_class.report(Rush::Status.new(1), err)
      described_class.report(Rush::Status.stopped(20), err)
      expect(err.string).to be_empty
    end

    it 'swallows a closed stderr but still hands the status back' do
      closed = instance_double(IO)
      allow(closed).to receive(:puts).and_raise(Errno::EBADF)
      status = killed(9)
      expect(described_class.report(status, closed)).to be(status)
    end
  end

  describe '.line' do
    it 'renders the common signals in dash vocabulary' do
      expect([described_class.line(killed(9)), described_class.line(killed(1))]).to eq(%w[Killed Hangup])
    end

    it 'renders user-defined signals like glibc strsignal' do
      expect(described_class.line(killed(10))).to eq('User defined signal 1')
    end
  end
end
