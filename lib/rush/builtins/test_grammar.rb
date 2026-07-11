# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # The historical `test`/`[` grammar, transcribed from dash's recursive
    # descent (oexpr/aexpr/nexpr/primary). POSIX leaves test beyond four
    # arguments unspecified and marks the -a/-o connectives obsolescent, but
    # countless real scripts use them, so rush reproduces dash here:
    #
    #   or      ::= and { "-o" and }         (both arms always evaluated)
    #   and     ::= not { "-a" not }
    #   not     ::= "!" not | primary
    #   primary ::= "(" or ")" | unary-op word | word binary-op word | word
    #
    # The cursor mirrors dash's t_wp pointer discipline: it rests on the last
    # consumed word, and a word left over after the parse is the "unexpected
    # operator" syntax error (TestError, exit 2). A missing operand after a
    # connective parses as the missing expression, which is false, so
    # `[ x -o ]` is true and `[ x -a ]` is false, exactly as in dash.
    class TestGrammar
      def initialize(args, files)
        @args = args
        @files = files
        @tokens = TestTokens.new(args)
        @pos = 0
      end

      def truth
        result = or_expr(kind_at(@pos))
        trailing = @args[@pos + 1]
        raise TestError, "#{trailing}: unexpected operator" if @args[@pos] && trailing

        result
      end

      private

      def kind_at(index)
        @tokens.kind_at(index)
      end

      def or_expr(kind)
        result = and_expr(kind)
        result = and_expr(kind_at(@pos += 2)) || result while connective == :bor
        result
      end

      def and_expr(kind)
        result = not_expr(kind)
        result = not_expr(kind_at(@pos += 2)) && result while connective == :band
        result
      end

      # The kind of the word after the cursor, or :eoi once the current word
      # is exhausted — dash's `if (!*t_wp) break; t_lex(t_wp + 1)`.
      def connective
        @args.fetch(@pos) { return :eoi }
        kind_at(@pos + 1)
      end

      def not_expr(kind)
        return primary(kind) unless kind == :bunop

        negand = kind_at(@pos + 1)
        @pos += 1 unless negand == :eoi
        !not_expr(negand)
      end

      # The missing expression is false, `(` opens a grouping, a unary
      # primary applies, and any other kind reads as a word primary.
      def primary(kind)
        case kind
        in :eoi then false
        in :lparen then group
        else kind == :unop ? unary : word
        end
      end

      def group
        inner = kind_at(@pos += 1)
        return false if inner == :rparen

        result = or_expr(inner)
        raise TestError, 'closing paren expected' unless kind_at(@pos += 1) == :rparen

        result
      end

      # The operand always exists: a unary primary with nothing after it is
      # demoted to a plain operand by TestTokens, never classified :unop.
      def unary
        op = current
        TestOperators.unary(op).call(@files, @args.fetch(@pos += 1))
      end

      # A word primary: a binary comparison when a binary primary follows,
      # otherwise the plain non-empty test of the word itself.
      def word
        return binary if kind_at(@pos + 1) == :binop

        !current.empty?
      end

      def binary
        lhs = current
        op = @args.fetch(@pos += 1)
        rhs = @args.fetch(@pos += 1) { raise TestError, "#{op}: argument expected" }
        TestOperators.apply_binary(op, lhs, rhs)
      end

      def current
        @args.fetch(@pos)
      end
    end
  end
end
