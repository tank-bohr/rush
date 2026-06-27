# frozen_string_literal: true

require 'open3'

# Exercises the real exe/rush in a child process so the fork-based features
# (pipelines) are validated end to end. Coverage of the forked children is not
# recorded by SimpleCov (a separate process); the in-process unit specs cover
# the child-side logic, and these specs confirm it actually works.
RSpec.describe 'rush real subprocess' do
  def project_root = File.expand_path('../..', __dir__)

  def run(source)
    out, _err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rush', '-c', source, chdir: project_root)
    [out, status.exitstatus]
  end

  it 'runs a multi-stage pipeline' do
    expect(run('echo hi | tr a-z A-Z | rev')).to eq(["IH\n", 0])
  end

  it 'returns the exit status of the last pipeline stage' do
    expect([run('true | false')[1], run('false | true')[1]]).to eq([1, 0])
  end

  it 'substitutes command output and strips trailing newlines' do
    expect(run('echo "[$(echo hi)]"')).to eq(["[hi]\n", 0])
  end
end
