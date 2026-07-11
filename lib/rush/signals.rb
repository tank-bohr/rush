# typed: true
# frozen_string_literal: true

module Rush
  # Resolves a trap signal spec to a single canonical name. Numbers map through
  # the POSIX signal table, names match case-insensitively and without a "SIG"
  # prefix, and 0/EXIT denote the pseudo-signal that fires when the shell exits.
  # An unknown spec resolves to nil so `trap` can report "bad trap" (dash parity).
  # Methods are explicit singletons: module_function would define a second,
  # instance-side copy that callers never reach — dead weight mutant proved
  # unkillable (journal, rush-211.8).
  module Signals
    extend T::Sig

    EXIT = 'EXIT'
    NUMBERS = {
      0 => EXIT, 1 => 'HUP', 2 => 'INT', 3 => 'QUIT', 4 => 'ILL', 5 => 'TRAP',
      6 => 'ABRT', 7 => 'BUS', 8 => 'FPE', 9 => 'KILL', 10 => 'USR1',
      11 => 'SEGV', 12 => 'USR2', 13 => 'PIPE', 14 => 'ALRM', 15 => 'TERM',
      17 => 'CHLD', 18 => 'CONT', 19 => 'STOP', 20 => 'TSTP', 21 => 'TTIN',
      22 => 'TTOU', 23 => 'URG', 24 => 'XCPU', 25 => 'XFSZ', 26 => 'VTALRM',
      27 => 'PROF', 28 => 'WINCH', 29 => 'IO', 30 => 'PWR', 31 => 'SYS'
    }.freeze
    NAMES = NUMBERS.invert.freeze

    sig { params(spec: String).returns(T.nilable(String)) }
    def self.decode(spec)
      return NUMBERS.fetch(Integer(spec, 10), nil) if spec.match?(/\A\d+\z/)

      name = spec.upcase
      NAMES.key?(name) ? name : nil
    end

    sig { params(name: String).returns(Integer) }
    def self.number(name)
      NAMES.fetch(name)
    end

    # strsignal(3)-style descriptions, as dash's jobs listing prints for a
    # signalled job ("Killed", "Terminated"). Only the common ones are
    # spelled out; the rest fall back to the signal name.
    DESCRIPTIONS = {
      1 => 'Hangup', 2 => 'Interrupt', 3 => 'Quit', 4 => 'Illegal instruction',
      5 => 'Trace/breakpoint trap', 6 => 'Aborted', 7 => 'Bus error',
      8 => 'Floating point exception', 9 => 'Killed', 10 => 'User defined signal 1',
      11 => 'Segmentation fault', 12 => 'User defined signal 2', 13 => 'Broken pipe',
      14 => 'Alarm clock', 15 => 'Terminated'
    }.freeze

    sig { params(number: Integer).returns(String) }
    def self.description(number)
      DESCRIPTIONS.fetch(number) { NUMBERS.fetch(number, "Signal #{number}") }
    end

    # strsignal(3) again, for the stop signals as the jobs listing shows a
    # Stopped entry: plain for ^Z's TSTP, qualified for the others (dash
    # prints the same strings, probed).
    STOPPED = {
      19 => 'Stopped (signal)', 20 => 'Stopped',
      21 => 'Stopped (tty input)', 22 => 'Stopped (tty output)'
    }.freeze

    sig { params(number: Integer).returns(String) }
    def self.stop_description(number)
      STOPPED.fetch(number, 'Stopped')
    end
  end
end
