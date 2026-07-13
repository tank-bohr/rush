# frozen_string_literal: true

require 'open3'
require 'tempfile'

# Exercises the real exe/rush in a child process so the fork-based features
# (pipelines) are validated end to end. Coverage of the forked children is not
# recorded by SimpleCov (a separate process); the in-process unit specs cover
# the child-side logic, and these specs confirm it actually works.
RSpec.describe 'rush real subprocess' do
  def project_root
    File.expand_path('../..', __dir__)
  end

  def run(source)
    out, _err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rush', '-c', source, chdir: project_root)
    [out, status.exitstatus]
  end

  def run_with_options(source, options)
    out, _err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rush', '-c', source,
                                       { chdir: project_root }.merge(options))
    [out, status.exitstatus]
  end

  it 'reports a fatal EXIT-trap error once without a Ruby backtrace' do
    out, err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rush', '-c', "trap 'echo X; shift' EXIT",
                                      chdir: project_root)
    expect([out, err, status.exitstatus]).to eq(["X\n", "rush: shift: can't shift that many\n", 2])
  end

  it 'runs a multi-stage pipeline' do
    expect(run('echo hi | tr a-z A-Z | rev')).to eq(["IH\n", 0])
  end

  it 'flushes a builtin in the last pipeline stage (forked child)' do
    expect(run('true | echo piped')).to eq(["piped\n", 0])
  end

  it 'returns the exit status of the last pipeline stage' do
    expect([run('true | false')[1], run('false | true')[1]]).to eq([1, 0])
  end

  it 'substitutes command output and strips trailing newlines' do
    expect(run('echo "[$(echo hi)]"')).to eq(["[hi]\n", 0])
  end

  it 'redirects to a parent-inherited fd and leaves it open for later commands' do
    Tempfile.create('rush-inherited-fd') do |file|
      expect(run_with_options('echo one >&9; echo two >&9; echo ok', 9 => file)).to eq(["ok\n", 0])
      file.rewind
      expect(file.read).to eq("one\ntwo\n")
    end
  end

  it 'makes an inherited-fd write visible to the next command, as dash writes straight to the fd (rush-erq)' do
    Tempfile.create('rush-inherited-fd') do |file|
      expect(run_with_options("echo one >&9; cat #{file.path}", 9 => file)).to eq(["one\n", 0])
    end
  end

  it 'persists an inherited fd duplicated by exec' do
    Tempfile.create('rush-inherited-fd') do |file|
      expect(run_with_options('exec 8>&9; echo via8 >&8; echo via9 >&9', 9 => file)).to eq(['', 0])
      file.rewind
      expect(file.read).to eq("via8\nvia9\n")
    end
  end

  it 'still treats an explicitly closed inherited fd as not open' do
    expect(run_with_options('true >&9; echo "rc=$?"', 9 => :close)).to eq(["rc=2\n", 0])
  end

  it 'runs a for loop with a conditional continue (external test)' do
    expect(run('for i in a b c; do if [ "$i" = b ]; then continue; fi; echo $i; done').first)
      .to eq("a\nc\n")
  end

  it 'runs a subshell, isolating variable changes and reporting its status' do
    expect(run('x=1; (x=2; echo $x); echo $x')).to eq(["2\n1\n", 0])
    expect(run('(exit 7); echo $?')).to eq(["7\n", 0])
  end
end
