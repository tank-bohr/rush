# frozen_string_literal: true

require 'tempfile'

# Invocation-level rush vs dash: option flags and $- rendering, the -s/-i and
# script-file sources, and malformed command lines — compared as
# [stdout, exitstatus]; stderr (dash's prompts and error wording) is ignored
# per project policy.
RSpec.describe 'rush vs dash (differential invocation corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  corpus = [
    [[], "echo [$-]\n"],
    [['-'], "echo lone-dash\n"],
    [['-e', '-'], "echo [$-]\n"],
    [['-s'], "echo [$-]\n"],
    [['-s', 'a', 'b'], 'echo "[$1-$2-$#]"'],
    [['-i'], "echo [$-]\n"],
    [['-i', '-c', 'echo [$-]'], nil],
    [['-e', '-c', 'echo [$-]'], nil],
    [['-ec', 'echo [$-]'], nil],
    [['-eu', '-c', 'echo [$-]'], nil],
    [['-o', 'errexit', '-c', 'echo [$-]'], nil],
    [['-e', '+e', '-c', 'echo [$-]; false; echo after'], nil],
    [['-e', '-c', 'false; echo after'], nil],
    [['-u', '-c', 'echo $nope; echo after'], nil],
    [['-c'], nil],
    [['-q', '-c', 'echo hi'], nil]
  ]

  corpus.each do |args, input|
    it "matches dash for `sh #{args.join(' ')}`#{' reading stdin' if input}" do
      expect(rush_argv(args, input)).to eq(dash_argv(args, input))
    end
  end

  it 'matches dash running a script file with operands' do
    Tempfile.create('rush-script') do |file|
      file.write("echo \"[$1-$#-$-]\"\n")
      file.flush
      args = [file.path, 'x', 'y']
      expect(rush_argv(args)).to eq(dash_argv(args))
    end
  end

  it 'matches dash status for a missing script file' do
    expect(rush_argv(['/nonexistent-rush-diff'])).to eq(dash_argv(['/nonexistent-rush-diff']))
  end
end
