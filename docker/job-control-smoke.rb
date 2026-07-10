#!/usr/bin/env ruby
# frozen_string_literal: true

# Job-control pty smoke (rush-mv8.3/.4): drive rush -i and dash -i identically on
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
#   - ^Z on a foreground job hands the prompt back with $? = 148, the job
#     parked Stopped in the table; exit is refused once ("You have stopped
#     jobs."); after a kill+CONT the job is waitable as 137 (rush-mv8.4)
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
      handover_picture.merge(stop_picture)
    end

    private

    def handover_picture
      { monitor_flags: single(/FLAGS:\[([a-z]+)\]/), self_leader: number(/GRP: (\d+)/) == pid,
        spawn_owns_tty: owns?('SPAWN'), pipeline_owns_tty: owns?('PIPE'), subshell_owns_tty: owns?('SUB'),
        cmdsub_tty_stays: number(/CS: (\d+)/) == pid, background_tty_stays: background_stays?,
        plus_m_flags: single(/FLAGS2:\[([a-z]+)\]/), plus_m_rejoins: rejoined?,
        alive_after: @buffer.include?('back:42'), exit_status: number(/WRAPPER:(\d+)/) }
    end

    def stop_picture
      { stop_signals_ignored: @buffer.include?('SIGS:adone'), ctrl_z_status: number(/ZST:(\d+)/),
        ctrl_z_job_listed: @buffer.include?('ZJOBS:stopped'),
        exit_refused: @buffer.include?('You have stopped jobs.'),
        refused_exit_status: number(/ZALIVE:(\d+)/), killed_job_waits: number(/ZW:(\d+)/) }
    end

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

  CTRL_Z = "\x1a"

  # Entries are pty lines, [raw-bytes, settle-delay] pairs (the ^Z), or
  # {sync:} barriers that wait for a marker to appear — the writer must not
  # outrun the shell (a slow interpreter start would otherwise let the ^Z
  # land on the wrong foreground job).
  SCRIPT = [
    'echo PID:$$',
    { sync: /PID:\d/ },
    'echo GRP: $(ps -o pgid= -p $$)',
    "sh -c 'sleep 0.2; echo SPAWN: $(ps -o pgid=,tpgid= -p $$)'",
    "sleep 0.3 | sh -c 'echo PIPE: $(ps -o pgid=,tpgid= -p $$)'",
    "(true; sh -c 'echo SUB: $(ps -o pgid=,tpgid= -p $$)'; true)",
    'echo CS: $(ps -o tpgid= -p $$)',
    "sh -c 'echo BG: $(ps -o pgid=,tpgid= -p $$)' & wait",
    "kill -TSTP $$; kill -TTOU $$; echo SIGS:a''done",
    'echo FLAGS:[$-]',
    { sync: /FLAGS:\[[a-z]+\]/ },
    # The line editor needs a beat to hand the (raw-mode) terminal back
    # before the ^Z can reach the line discipline as a signal.
    ["sleep 100\r", 1.2],
    [CTRL_Z, 1.0],
    'echo ZST:$?',
    { sync: /ZST:\d/ },
    'j=$(mktemp); jobs > "$j"; grep -q Stopped "$j" && echo ZJOBS:stopped; rm -f "$j"',
    'exit',
    'echo ZALIVE:$?',
    # One line, no prompt in between: dash's pre-prompt notification would
    # otherwise report-and-free the killed entry (that column arrives for
    # rush with mv8.6) and wait %% would answer "no current job" instead.
    'kill -9 %%; kill -CONT %%; sleep 0.2; wait %%; echo ZW:$?',
    { sync: /ZW:\d/ },
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
    ctrl_z_status: 148, ctrl_z_job_listed: true, exit_refused: true, refused_exit_status: 0,
    killed_job_waits: 137,
    plus_m_flags: 'si', plus_m_rejoins: true, alive_after: true, exit_status: 7
  }.freeze

  def run
    rush = Transcript.new(drive('rush', 'bundle exec ruby -Ilib exe/rush')).picture
    dash = Transcript.new(drive('dash', 'dash')).picture
    [['dash (oracle sanity)', dash], ['rush', rush]].each { |label, seen| verify(label, seen) }
    puts 'rush job-control pty smoke ok: monitor by default, terminal follows every foreground job ' \
         '(spawn/pipeline/subshell), stays home for cmdsub/background, TSTP+TTOU ignored, ' \
         '^Z parks a Stopped job ($?=148, exit refused once, waitable after kill), ' \
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
    SCRIPT.each { |entry| type(inp, entry) }
    Process.waitpid(pid)
  end

  def type(inp, entry)
    return await_marker(entry.fetch(:sync)) if entry.is_a?(Hash)
    return press(inp, *entry) if entry.is_a?(Array)

    press(inp, "#{entry}\r", 0.45)
  end

  def press(inp, raw, delay)
    inp.write(raw)
    sleep delay
  end

  # The overall Timeout still bounds a marker that never comes.
  def await_marker(pattern)
    sleep 0.2 until @buffer.match?(pattern)
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
