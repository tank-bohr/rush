# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `read [-r] var ...` — read a logical line from stdin, split it on IFS and
    # assign the fields to the named variables (the last variable takes the
    # remainder). Without -r a backslash preserves the next character (shielding
    # it from field splitting) and a trailing backslash continues onto the next
    # physical line; with -r the line is taken verbatim. Returns non-zero when
    # end of file arrives before a newline (assigning what was read); with no
    # variable operand it is an error.
    class Read < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        return usage_error if names.empty?

        chars, complete = ReadInput.new(stdin, raw?).call
        assign(chars)
        complete ? success : failure
      end

      private

      sig { returns(T::Boolean) }
      def raw?
        operands.first == '-r'
      end

      sig { returns(T::Array[String]) }
      def names
        raw? ? operands.drop(1) : operands
      end

      sig { params(chars: T::Array[Expansion::ReadChar]).void }
      def assign(chars)
        fields = Expansion::ReadSplitter.new(ifs, names.size).split(chars)
        names.each_with_index { |name, index| executor.state.variables.assign(name, fields.fetch(index)) }
      end

      sig { returns(T.nilable(String)) }
      def ifs
        executor.state.variables.get('IFS')
      end

      sig { returns(T.untyped) }
      def stdin
        io.get(0)
      end

      sig { returns(Status) }
      def usage_error
        stderr.puts('rush: read: arg count')
        failure(2)
      end
    end
  end
end
