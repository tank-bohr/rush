# frozen_string_literal: true

require 'tmpdir'

# POSIX 2.8.1 "Consequences of Shell Errors", the interactive column: rush -i
# vs dash -i reading a piped script. Every error class must report, publish
# its status as $?, and return to the prompt instead of exiting; EOF ends the
# session with the last status. Prompts and diagnostics land on stderr, which
# the comparison ignores per project policy. Startup files are compared via
# controlled ENV files only — login profiles read the real /etc/profile,
# which is host-sensitive (see docs/journal.md).
RSpec.describe 'rush vs dash (differential interactive-error corpus)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  corpus = [
    "fi\necho [$?]\n",                        # shell language syntax error
    "set -u\necho $nope\necho after $?\n",    # expansion error
    "readonly x=1\nx=2\necho after $?\n",     # variable assignment error
    "readonly x=1\nunset x\necho after $?\n",
    "true >&7\necho after $?\n",              # redirection error
    "nosuchcmd_rush_xyz\necho after $?\n",    # command not found
    "shift 5\necho after $?\n",               # special-builtin utility error
    "exit abc\necho after\n",
    ". /nonexistent-rush\necho after $?\n",   # dot script not found
    "eval 'bad )'\necho after $?\n",
    "cd /nonexistent-rush\necho after $?\n",
    "false\n",                                # EOF exits with the last status
    "set -e\nfalse\necho never\n"             # errexit still exits an interactive shell
  ]

  corpus.each do |script|
    it "matches dash -i for #{script.inspect}" do
      expect(rush_argv(['-i'], script)).to eq(dash_argv(['-i'], script))
    end
  end

  it 'matches dash reading the ENV file for interactive shells only' do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/envrc", "echo env-ran\n")
      env = { 'ENV' => "#{dir}/envrc" }
      expect(rush_argv(['-i'], "echo main\n", env)).to eq(dash_argv(['-i'], "echo main\n", env))
      expect(rush_argv([], "echo main\n", env)).to eq(dash_argv([], "echo main\n", env))
    end
  end

  it 'matches dash expanding parameters in the ENV value' do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/envrc", "echo env-ran\n")
      env = { 'RUSH_TEST_DIR' => dir, 'ENV' => '$RUSH_TEST_DIR/envrc' }
      expect(rush_argv(['-i'], "echo main\n", env)).to eq(dash_argv(['-i'], "echo main\n", env))
    end
  end

  it 'matches dash running ENV for an interactive -c command' do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/envrc", "echo env-ran\n")
      env = { 'ENV' => "#{dir}/envrc" }
      expect(rush_argv(['-i', '-c', 'echo main'], nil, env))
        .to eq(dash_argv(['-i', '-c', 'echo main'], nil, env))
    end
  end
end
