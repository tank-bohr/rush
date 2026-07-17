# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `getopts optstring name [args...]` — parse one POSIX short option per call,
    # storing the option in `name`, the next public position in OPTIND and any
    # option argument in OPTARG. A leading ':' in optstring enables silent error
    # mode for bad options / missing arguments.
    class Getopts < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        return usage if operands.size < 2

        apply(GetoptsParser.new(state: state, optstring: optstring, arguments: arguments, optind: optind).call)
      end

      private

      sig { returns(Status) }
      def usage
        report('getopts: Usage: getopts optstring var [arg...]')
        failure(2)
      end

      sig { params(result: GetoptsParser::Result).returns(Status) }
      def apply(result)
        store(result)
        report_message(result.message)
        Status.new(result.exitstatus)
      end

      # The variable updates a getopts step produces: `name`, OPTARG, OPTIND.
      sig { params(result: GetoptsParser::Result).void }
      def store(result)
        variables.assign(name, result.name)
        update_optarg(result.optarg) unless result.keep_optarg
        variables.assign('OPTIND', result.optind.to_s)
      end

      sig { params(value: T.nilable(String)).void }
      def update_optarg(value)
        value ? variables.assign('OPTARG', value) : variables.unset('OPTARG')
      end

      sig { params(message: T.nilable(String)).void }
      def report_message(message)
        report(message) if message
      end

      sig { params(message: String).void }
      def report(message)
        stderr.puts(message)
      rescue Errno::EBADF
        nil
      end

      sig { returns(Integer) }
      def optind
        value = Integer(variables.get('OPTIND') || '1', 10)
        value.positive? ? value : 1
      rescue ArgumentError
        1
      end

      sig { returns(T::Array[String]) }
      def arguments
        operands.drop(2).empty? ? executor.state.positional.to_a : operands.drop(2)
      end

      sig { returns(String) }
      def optstring
        operands.fetch(0)
      end

      sig { returns(String) }
      def name
        operands.fetch(1)
      end

      sig { returns(GetoptsState) }
      def state
        executor.state.getopts
      end

      sig { returns(ShellVariables) }
      def variables
        executor.state.variables
      end
    end
  end
end
