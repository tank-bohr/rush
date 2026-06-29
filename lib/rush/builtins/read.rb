# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `read [-r] var ...` — read a line from stdin, split it on IFS and assign the
    # fields to the named variables (the last variable takes the remainder).
    # Without -r a backslash escapes the next character. Returns non-zero at end
    # of file (clearing the variables); with no variable operand it is an error.
    class Read < Base
      def call
        return usage_error if names.empty?

        line = stdin.gets
        assign(cook(line))
        line ? success : failure
      end

      private

      def raw?
        operands.first == '-r'
      end

      def names
        raw? ? operands.drop(1) : operands
      end

      def cook(line)
        line ? strip_escapes(line.chomp) : ''
      end

      def strip_escapes(text)
        raw? ? text : text.gsub(/\\(.)/m, '\1').delete_suffix('\\')
      end

      def assign(line)
        fields = Expansion::ReadSplitter.new(ifs, names.size).split(line)
        names.each_with_index { |name, index| executor.state.environment.assign(name, fields[index]) }
      end

      def ifs
        executor.state.environment.get('IFS')
      end

      def stdin
        io.get(0)
      end

      def usage_error
        stderr.puts('rush: read: arg count')
        failure(2)
      end
    end
  end
end
