# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # One `pattern|pattern) body ;;` arm of a case statement.
    CaseItem = Data.define(:patterns, :body)

    # `case word in pattern) body ;; ... esac`. Expands the subject, then runs the
    # body of the first arm with a pattern (fnmatch glob) that matches it; no
    # match yields status 0. There is no fall-through.
    class Case < Node
      extend T::Sig

      attr_reader :word, :items

      sig { params(word: Word, items: T::Array[CaseItem]).void }
      def initialize(word, items)
        super()
        @word = word
        @items = items
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        subject = executor.expander.expand_value(word)
        item = items.find { |candidate| matches?(executor, candidate, subject) }
        item ? executor.run(item.body) : Status.success
      end

      private

      sig { params(executor: Executor, item: CaseItem, subject: String).returns(T::Boolean) }
      def matches?(executor, item, subject)
        item.patterns.any? { |pattern| executor.system.fnmatch(executor.expander.expand_value(pattern), subject) }
      end
    end
  end
end
