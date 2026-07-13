# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `read [-r] var ...` — read a logical line from stdin, split it on IFS and
    # assign the fields to the named variables (the last variable takes the
    # remainder). Repeated or clustered `-r` flags are accepted and `--` ends
    # option parsing; any other option or an invalid variable name is a usage
    # error. Without -r a backslash preserves the next character (shielding it
    # from field splitting) and a trailing backslash continues onto the next
    # physical line; with -r the line is taken verbatim. Returns non-zero when
    # end of file arrives before a newline (assigning what was read).
    class Read < Base
      extend T::Sig

      NAME = /\A[A-Za-z_]\w*\z/

      sig { returns(Status) }
      def call
        parsed = parse_operands
        return usage_error unless valid?(parsed)

        raw, names = T.must(parsed)
        read_and_assign(raw, names)
      end

      private

      sig { returns(T.nilable([T::Boolean, T::Array[String]])) }
      def parse_operands
        args = operands.dup
        mode = consume_options(args)
        return if mode == :invalid

        [mode == :raw, args]
      end

      sig { params(args: T::Array[String], mode: Symbol).returns(Symbol) }
      def consume_options(args, mode: :cooked)
        return mode unless option?(option = args.first)

        args.shift
        return mode if option == '--'
        return :invalid unless option.to_s.delete_prefix('-').chars.all?('r')

        consume_options(args, mode: :raw)
      end

      sig { params(arg: T.nilable(String)).returns(T::Boolean) }
      def option?(arg)
        !!arg&.start_with?('-') && arg != '-'
      end

      sig { params(parsed: T.nilable([T::Boolean, T::Array[String]])).returns(T::Boolean) }
      def valid?(parsed)
        !!parsed && parsed.last.any? && parsed.last.all? { |name| name.match?(NAME) }
      end

      sig { params(raw: T::Boolean, names: T::Array[String]).returns(Status) }
      def read_and_assign(raw, names)
        result = ReadInput.new(stdin, raw, pending: -> { executor.trap_runner.pending? }).call
        return failure unless result

        chars, complete = result
        assign(chars, names)
        complete ? success : failure
      end

      sig { params(chars: T::Array[Expansion::ReadChar], names: T::Array[String]).void }
      def assign(chars, names)
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
