# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # Pure evaluator for `test`/`[` expressions. POSIX specifies the result
    # by argument count (XCU test), so #evaluate applies that table in dash's
    # order: at three arguments a binary primary outranks any other reading;
    # a leading `!` at three or four arguments negates the rest (re-checked,
    # so `! a = b` reads as the negated compare); a full `( ... )` wrapper at
    # three or four arguments drops to its contents. Everything else — zero
    # to two arguments and the shapes POSIX leaves unspecified — is handed to
    # TestGrammar, the transcription of dash's recursive descent. A malformed
    # expression raises TestError, which the builtin maps to exit 2.
    #
    # One deliberate divergence, on POSIX's side: dash zeroes (rather than
    # toggles) its negation parity when it peels `!` twice, so `[ ! ! ! x ]`
    # is true and `[ ! ! -n x ]` false there; POSIX defines the four-argument
    # `!` form as the negated three-argument test, so rush negates honestly.
    # Pinned in the unit specs.
    class TestExpr
      def initialize(args, files)
        @args = args
        @files = files
      end

      def true?
        evaluate(@args)
      end

      private

      # A binary primary at exactly three arguments outranks every other
      # reading; only then do the `!` and `( ... )` rows apply.
      def evaluate(args)
        return binary(args) if shortcut?(args)

        peel(args)
      end

      def shortcut?(args)
        args.size == 3 && TestOperators.binary?(args[1])
      end

      def peel(args)
        return !evaluate(args.drop(1)) if negation?(args)
        return grammar(args[1...-1].to_a) if wrapped?(args)

        grammar(args)
      end

      # `!` peels only at three or four arguments (POSIX's 3- and 4-argument
      # rows); at other lengths the grammar owns `!` with tighter binding.
      def negation?(args)
        (3..4).cover?(args.size) && args.first == '!'
      end

      # A full `( ... )` wrapper likewise drops to its contents only at three
      # or four arguments; longer groupings are parsed as grammar primaries.
      def wrapped?(args)
        (3..4).cover?(args.size) && args.first == '(' && args.last == ')'
      end

      def binary(args)
        args => [lhs, op, rhs]
        TestOperators.apply_binary(op, lhs, rhs)
      end

      def grammar(args)
        TestGrammar.new(args, @files).truth
      end
    end
  end
end
