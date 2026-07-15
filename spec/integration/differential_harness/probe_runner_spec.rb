# frozen_string_literal: true

require 'shellwords'
require 'tempfile'

RSpec.describe DifferentialHarness::ProbeRunner do
  let(:child_pids) { [] }

  after { child_pids.each { |pid| kill(pid) } }

  it 'returns stdout, stdin/env behavior and the exact exit status' do
    argv = ['sh', '-c', 'read line; printf "%s:%s" "$TOKEN" "$line"; exit 7']
    result = described_class.call(argv, "input\n", { 'TOKEN' => 'value' }, pgroup: true)
    expect(result).to eq(['value:input', 7])
  end

  it 'preserves a nil exitstatus when a probe dies from a signal' do
    result = described_class.call(['sh', '-c', 'kill -TERM $$'], '', {}, pgroup: true)
    expect(result).to eq(['', nil])
  end

  it 'keeps ordinary probes in the current session but gives them an owned group' do
    pid, group, session = process_identity([RbConfig.ruby, '-e', identity_source], pgroup: true)
    expect([group == pid, session]).to eq([true, Process.getsid])
  end

  it 'keeps setsid probes in their explicit isolated session' do
    pid, group, session = process_identity(['setsid', RbConfig.ruby, '-e', identity_source])
    expect([group, session]).to eq([pid, pid])
  end

  it 'times out and kills a stopped descendant process group' do
    stub_const('DifferentialHarness::ProbeRunner::TIMEOUT', 3.0)
    Tempfile.create('rush-probe-pid') do |file|
      child = "echo $$ > #{Shellwords.escape(file.path)}; kill -STOP $$"
      argv = ['sh', '-c', "sh -c #{Shellwords.escape(child)} & wait"]
      expect { described_class.call(argv, '', {}, pgroup: true) }.to raise_error(DifferentialHarness::ProbeTimeout)
      pid = track(read_written_pid(file))
      expect(wait_until_gone?(pid)).to be(true)
    end
  end

  it 'kills a stopped descendant that creates a separate process group' do
    stub_const('DifferentialHarness::ProbeRunner::TIMEOUT', 3.0)
    Tempfile.create('rush-probe-pid') do |file|
      source = 'child=fork do; Process.setpgrp; Signal.trap("HUP", "IGNORE"); ' \
               'File.write(ARGV[0], Process.pid); Process.kill("STOP", Process.pid); end; Process.wait(child)'
      argv = [RbConfig.ruby, '-e', source, file.path]
      expect { described_class.call(argv, '', {}, pgroup: true) }.to raise_error(DifferentialHarness::ProbeTimeout)
      pid = track(read_written_pid(file))
      expect(wait_until_gone?(pid)).to be(true)
    end
  end

  it 'cleans a reparented escapee after its leader exits normally' do
    Tempfile.create('rush-probe-pid') do |file|
      source = 'fork do; Process.setpgrp; Signal.trap("HUP", "IGNORE"); STDOUT.reopen("/dev/null"); ' \
               'STDERR.reopen("/dev/null"); File.write(ARGV[0], Process.pid); ' \
               'Process.kill("STOP", Process.pid); end; sleep 0.001 until File.size?(ARGV[0])'
      result = described_class.call([RbConfig.ruby, '-e', source, file.path], '', {}, pgroup: true)
      pid = track(Integer(File.read(file.path)))
      expect([result, wait_until_gone?(pid)]).to eq([['', 0], true])
    end
  end

  it 'cleans the group even after its leader exits normally' do
    argv = ['sh', '-c', 'sleep 30 >/dev/null 2>&1 & echo $!']
    output, status = described_class.call(argv, '', {}, pgroup: true)
    pid = track(Integer(output))
    expect([status, wait_until_gone?(pid)]).to eq([0, true])
  end

  it 'does not adopt or kill another child of the RSpec process' do
    pid = Process.spawn('sleep', '5')
    result = described_class.call(['sh', '-c', 'printf ok'], '', {}, pgroup: true)
    expect([result, gone?(pid)]).to eq([['ok', 0], false])
  ensure
    kill(pid) if pid
    reap(pid) if pid
  end

  it 'does not hold unrelated RSpec file descriptors open' do
    Tempfile.create('rush-probe-ready') do |file|
      reader, writer = IO.pipe
      command = "printf ready > #{Shellwords.escape(file.path)}; sleep 0.3"
      probe = Thread.new { described_class.call(['sh', '-c', command], '', {}, pgroup: true) }
      sleep(0.01) until File.size?(file.path)
      writer.close
      expect([reader.wait_readable(0.1), reader.eof?]).to eq([reader, true])
      probe.join
      reader.close
    end
  end

  def process_identity(argv, spawn_options = {})
    output, = described_class.call(argv, '', {}, spawn_options)
    output.split.map { |value| Integer(value) }
  end

  def identity_source
    'puts [Process.pid, Process.getpgrp, Process.getsid].join(" ")'
  end

  def track(pid)
    child_pids << pid
    pid
  end

  # The descendant races the stubbed probe timeout to write its pidfile; on a
  # loaded runner interpreter start-up can lose that race, so give the write a
  # grace window after the timeout fires instead of reading immediately.
  def read_written_pid(file)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    sleep(0.01) until File.size?(file.path) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    Integer(File.read(file.path))
  end

  def wait_until_gone?(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    sleep(0.01) until gone?(pid) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    gone?(pid)
  end

  def gone?(pid)
    Process.kill(0, pid)
    false
  rescue Errno::ESRCH
    true
  end

  def kill(pid)
    Process.kill('KILL', pid) unless gone?(pid)
  rescue Errno::ESRCH
    nil
  end

  def reap(pid)
    Process.waitpid(pid)
  rescue Errno::ECHILD
    nil
  end
end
