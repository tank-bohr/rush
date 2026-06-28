# frozen_string_literal: true

module Rush
  module Builtins
    # `times` — write the accumulated CPU times: line 1 the shell's own user and
    # system time, line 2 the user and system time of its children, each formatted
    # `<min>m<sec>s <min>m<sec>s` with six-decimal seconds (POSIX, matching dash).
    # The values are non-deterministic, so behaviour is verified by format.
    class Times < Base
      def call
        t = executor.system.times
        stdout.puts("#{clock(t.utime)} #{clock(t.stime)}")
        stdout.puts("#{clock(t.cutime)} #{clock(t.cstime)}")
        success
      end

      private

      def clock(seconds)
        minutes = (seconds / 60).to_i
        format('%<min>dm%<sec>fs', min: minutes, sec: seconds - (minutes * 60))
      end
    end
  end
end
