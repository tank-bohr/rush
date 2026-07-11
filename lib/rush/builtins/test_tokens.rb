# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # Positional word classification for `test`/`[`, mirroring dash's t_lex:
    # a word is an operator only in operator position. A unary primary is
    # demoted to a plain operand when it is the last word (`[ -n ]` is the
    # non-empty test of "-n") or when a binary primary follows with more
    # beyond (`[ -t = -t ]` compares strings); a `(` closing the argument
    # list is likewise a word. Everything else keeps its table kind: unary
    # and binary primaries, `!`, the XSI-obsolescent -a/-o connectives, and
    # the parentheses.
    class TestTokens
      extend T::Sig

      KINDS = T.let({ '!' => :bunop, '-a' => :band, '-o' => :bor,
                      '(' => :lparen, ')' => :rparen }.freeze, T::Hash[String, Symbol])

      # The t_lex demotion rules, keyed by table kind (a registry, so the
      # classifier itself never branches on the kind it is computing).
      DEMOTIONS = T.let({
        unop: ->(args, index) { operand_position?(args, index) },  #: ^(Array[String], Integer) -> bool
        lparen: ->(args, index) { args[index + 1].nil? }           #: ^(Array[String], Integer) -> bool
      }.freeze, T::Hash[Symbol, T.proc.params(args: T::Array[String], index: Integer).returns(T::Boolean)])

      NEVER = T.let(->(_args, _index) { false },
                    T.proc.params(args: T::Array[String], index: Integer).returns(T::Boolean))

      sig { params(args: T::Array[String]).void }
      def initialize(args)
        @args = args
      end

      sig { params(index: Integer).returns(Symbol) }
      def kind_at(index)
        positional(@args.fetch(index) { return :eoi }, index)
      end

      # dash's isoperand: a unary primary reads as an operand when nothing
      # follows, or when the next word is a binary primary and more follows.
      sig { params(args: T::Array[String], index: Integer).returns(T::Boolean) }
      def self.operand_position?(args, index)
        following = args.fetch(index + 1) { return true }
        args.fetch(index + 2) { return false }
        TestOperators.binary?(following)
      end
      private_class_method :operand_position?

      private

      sig { params(word: String, index: Integer).returns(Symbol) }
      def positional(word, index)
        kind = KINDS[word] || primary_kind(word)
        return :operand if DEMOTIONS.fetch(kind, NEVER).call(@args, index)

        kind
      end

      sig { params(word: String).returns(Symbol) }
      def primary_kind(word)
        return :unop if TestOperators.unary?(word)
        return :binop if TestOperators.binary?(word)

        :operand
      end
    end
  end
end
