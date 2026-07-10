# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # fg and bg (POSIX User Portability utilities) without the terminal half
    # of job control: resolve the target like dash — an empty table is "No
    # current job" — then refuse, because no job here was created under job
    # control. Always status 2, the shell carries on. One class serves both
    # names; argv[0] prefixes the diagnostic.
    class NoJobControl < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        spec = operands.first
        JobSpec.resolve(executor.jobs, spec || '%+')
        bad(refusal(spec))
      rescue JobError => e
        bad(e.message)
      end

      private

      sig { params(spec: T.nilable(String)).returns(String) }
      def refusal(spec)
        spec ? "job #{spec} not created under job control" : 'job not created under job control'
      end

      sig { params(message: String).returns(Status) }
      def bad(message)
        stderr.puts("#{argv.fetch(0)}: #{message}")
        failure(2)
      end
    end
  end
end
