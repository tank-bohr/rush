# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # The parsed option prefix of the `command` builtin's argv: leading
    # clusters of -p / -v / -V letters (repeats accumulate; -V outranks -v,
    # as in dash), an optional `--` terminator, then the operands. A letter
    # outside the set is recorded as `illegal` (e.g. '-z'), which `command`
    # reports with status 2; `+x` or a lone `-` is an operand, not options.
    class CommandOptions
      extend T::Sig

      LETTERS = T.let({ 'p' => :default_path, 'v' => :verify, 'V' => :verbose }.freeze,
                      T::Hash[String, Symbol])

      # A dash followed by letters, except the bare `--` terminator (a lone
      # dash or a +cluster is an operand — dash-probed).
      CLUSTER = /\A-(?!-\z)./

      sig { returns(T::Array[String]) }
      attr_reader :operands

      sig { returns(T.nilable(String)) }
      attr_reader :illegal

      sig { params(args: T::Array[String]).void }
      def initialize(args)
        @args = args
        @flags = T.let([], T::Array[Symbol])
        @illegal = T.let(nil, T.nilable(String))
        @operands = T.let(consume, T::Array[String])
      end

      sig { returns(T.nilable(String)) }
      def name
        operands.first
      end

      sig { returns(T::Boolean) }
      def default_path?
        @flags.include?(:default_path)
      end

      sig { returns(T::Boolean) }
      def verify?
        @flags.include?(:verify)
      end

      sig { returns(T::Boolean) }
      def verbose?
        @flags.include?(:verbose)
      end

      private

      sig { returns(T::Array[String]) }
      def consume
        index = count_clusters
        @args.drop(arg_at(index) == '--' ? index + 1 : index)
      end

      sig { returns(Integer) }
      def count_clusters
        index = 0
        index += 1 while take(index)
        index
      end

      sig { params(index: Integer).returns(T::Boolean) }
      def take(index)
        return false unless cluster?(index)

        arg_at(index).chars.drop(1).all? { |letter| record(letter) }
      end

      sig { params(index: Integer).returns(T::Boolean) }
      def cluster?(index)
        arg_at(index).match?(CLUSTER)
      end

      sig { params(index: Integer).returns(String) }
      def arg_at(index)
        @args.fetch(index, '')
      end

      # The letter's flag (feeding take's all?-driven cluster scan), nil once
      # the letter proves illegal.
      sig { params(letter: String).returns(T.nilable(Symbol)) }
      def record(letter)
        flag = LETTERS.fetch(letter) { record_illegal(letter) }
        @flags << flag if flag
        flag
      end

      sig { params(letter: String).returns(NilClass) }
      def record_illegal(letter)
        @illegal = "-#{letter}"
        nil
      end
    end
  end
end
