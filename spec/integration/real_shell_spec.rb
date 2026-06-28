# frozen_string_literal: true

require 'open3'

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

  it 'runs a for loop with a conditional continue (external test)' do
    expect(run('for i in a b c; do if [ "$i" = b ]; then continue; fi; echo $i; done').first)
      .to eq("a\nc\n")
  end

  it 'runs a subshell, isolating variable changes and reporting its status' do
    expect(run('x=1; (x=2; echo $x); echo $x')).to eq(["2\n1\n", 0])
    expect(run('(exit 7); echo $?')).to eq(["7\n", 0])
  end
end
