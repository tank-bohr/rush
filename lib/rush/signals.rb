# typed: true
# frozen_string_literal: true

module Rush
  # Resolves a trap signal spec to a single canonical name. Numbers map through
  # the POSIX signal table, names match case-insensitively and without a "SIG"
  # prefix, and 0/EXIT denote the pseudo-signal that fires when the shell exits.
  # An unknown spec resolves to nil so `trap` can report "bad trap" (dash parity).
  module Signals
    module_function

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

    def decode(spec)
      return NUMBERS[spec.to_i] if spec.match?(/\A\d+\z/)

      name = spec.upcase
      NAMES.key?(name) ? name : nil
    end

    def number(name)
      NAMES.fetch(name)
    end
  end
end
