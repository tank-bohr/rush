# frozen_string_literal: true

module Rush
  module Builtins
    # `times` — write the accumulated CPU times: line 1 the shell's own user and
    # system time, line 2 the user and system time of its children, each formatted
    # `<min>m<sec>s <min>m<sec>s` with six-decimal seconds (POSIX, matching dash).
    # The values are non-deterministic, so behaviour is verified by format.
    class Times < Base
      def call
        tms = executor.system.times
        stdout.puts("#{clock(tms.utime)} #{clock(tms.stime)}")
        stdout.puts("#{clock(tms.cutime)} #{clock(tms.cstime)}")
        success
      end

      private

      def clock(seconds)
        minutes, secs = seconds.divmod(60)
        format('%<min>dm%<sec>fs', min: minutes, sec: secs)
      end
    end
  end
end
