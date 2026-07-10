#!/usr/bin/env ruby
# frozen_string_literal: true

# Job-control pty smoke (rush-mv8.3): drive rush -i and dash -i identically on
# a real pseudo-terminal and compare the terminal-handover picture — the
# boundary no in-process spec can reach (tcsetpgrp/tcgetpgrp are :nocov:).
#
# Each shell runs wrapped in `sh -c '<shell> -i; ...'` so it is neither the
# session leader nor an orphaned process group: stop signals then behave for
# real (an orphaned group discards TSTP/TTOU, masking a broken disposition).
#
# Asserted, for both shells alike:
#   - interactive default monitor: $- carries s, m, i; the shell self-leaders
#   - a spawned command, a pipeline and a subshell each own the terminal
#     while they run (job pgid == tpgid != shell pid)
#   - command substitution and background jobs leave the tty with the shell
#   - TSTP and TTOU cannot stop the shell under -m
#   - set +m drops m from $-, rejoins the original group and hands the
#     terminal back; the session keeps working after every handover
#   - the exit status survives the whole dance
require 'pty'
require 'timeout'

# Drives each shell through the same script on a pty and compares pictures.
class JobControlSmoke
  # One shell's pty transcript, read back as its terminal-handover picture.
  class Transcript
    def initialize(buffer)
      @buffer = buffer
    end

    def picture
      { monitor_flags: single(/FLAGS:\[([a-z]+)\]/), self_leader: number(/GRP: (\d+)/) == pid,
        spawn_owns_tty: owns?('SPAWN'), pipeline_owns_tty: owns?('PIPE'), subshell_owns_tty: owns?('SUB'),
        cmdsub_tty_stays: number(/CS: (\d+)/) == pid, background_tty_stays: background_stays?,
        stop_signals_ignored: @buffer.include?('SIGS:adone'), plus_m_flags: single(/FLAGS2:\[([a-z]+)\]/),
        plus_m_rejoins: rejoined?, alive_after: @buffer.include?('back:42'),
        exit_status: number(/WRAPPER:(\d+)/) }
    end

    private

    def pid
      @pid ||= number(/PID:(\d+)/)
    end

    def owns?(tag)
      group, foreground = pair(tag)
      group == foreground && group != pid
    end

    def background_stays?
      group, foreground = pair('BG')
      group != foreground && foreground == pid
    end

    def rejoined?
      group, foreground = pair('OFF')
      group == foreground && group != pid
    end

    def pair(tag)
      match = @buffer.match(/#{tag}: (\d+) (\d+)/) or abort "job-control smoke: no '#{tag}:' line in:\n#{@buffer}"
      [Integer(match[1], 10), Integer(match[2], 10)]
    end

    def single(pattern)
      match = @buffer.match(pattern) or abort "job-control smoke: no #{pattern} in:\n#{@buffer}"
      match[1]
    end

    def number(pattern)
      Integer(single(pattern), 10)
    end
  end

  SCRIPT = [
    'echo PID:$$',
    'echo GRP: $(ps -o pgid= -p $$)',
    "sh -c 'sleep 0.2; echo SPAWN: $(ps -o pgid=,tpgid= -p $$)'",
    "sleep 0.3 | sh -c 'echo PIPE: $(ps -o pgid=,tpgid= -p $$)'",
    "(true; sh -c 'echo SUB: $(ps -o pgid=,tpgid= -p $$)'; true)",
    'echo CS: $(ps -o tpgid= -p $$)',
    "sh -c 'echo BG: $(ps -o pgid=,tpgid= -p $$)' & wait",
    "kill -TSTP $$; kill -TTOU $$; echo SIGS:a''done",
    'echo FLAGS:[$-]',
    'set +m',
    'echo FLAGS2:[$-]',
    "sh -c 'echo OFF: $(ps -o pgid=,tpgid= -p $$)'",
    'echo back:$((6*7))',
    'exit 7'
  ].freeze

  EXPECTED = {
    monitor_flags: 'smi', self_leader: true,
    spawn_owns_tty: true, pipeline_owns_tty: true, subshell_owns_tty: true,
    cmdsub_tty_stays: true, background_tty_stays: true, stop_signals_ignored: true,
    plus_m_flags: 'si', plus_m_rejoins: true, alive_after: true, exit_status: 7
  }.freeze

  def run
    rush = Transcript.new(drive('rush', 'bundle exec ruby -Ilib exe/rush')).picture
    dash = Transcript.new(drive('dash', 'dash')).picture
    [['dash (oracle sanity)', dash], ['rush', rush]].each { |label, seen| verify(label, seen) }
    puts 'rush job-control pty smoke ok: monitor by default, terminal follows every foreground job ' \
         '(spawn/pipeline/subshell), stays home for cmdsub/background, TSTP+TTOU ignored, ' \
         'set +m restores — byte-for-byte the dash picture'
  end

  private

  def drive(label, launch)
    @label = label
    @buffer = +''
    PTY.spawn('sh', '-c', "#{launch} -i; echo WRAPPER:$?") { |out, inp, pid| session(out, inp, pid) }
    # Reline paints the line with cursor-control sequences; strip them so
    # the marker regexps see the shell's actual output.
    @buffer.gsub(/\e\[[0-9;?]*[a-zA-Z]/, '')
  end

  def session(out, inp, pid)
    reader = reader_thread(out)
    feed(inp, pid)
    sleep 0.2
    reader.kill
  end

  def reader_thread(out)
    Thread.new do
      loop { @buffer << out.readpartial(4096) }
    rescue EOFError, Errno::EIO
      nil
    end
  end

  def feed(inp, pid)
    Timeout.timeout(60) { run_script(inp, pid) }
  rescue Timeout::Error
    kill_hard(pid)
    abort "job-control smoke: #{@label} stopped or hung; transcript:\n#{@buffer}"
  end

  def run_script(inp, pid)
    SCRIPT.each do |line|
      inp.write("#{line}\r")
      sleep 0.45
    end
    Process.waitpid(pid)
  end

  def kill_hard(pid)
    Process.kill('KILL', pid)
  rescue Errno::ESRCH
    nil
  end

  def verify(label, seen)
    return if seen == EXPECTED

    diff = EXPECTED.keys.reject { |key| seen[key] == EXPECTED[key] }
    abort "job-control smoke: #{label} diverges on #{diff.join(', ')}:\n" \
          "expected #{EXPECTED.slice(*diff)}\n     " \
          "got #{seen.slice(*diff)}"
  end
end

JobControlSmoke.new.run
