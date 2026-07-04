# typed: true

# Data.define value objects whose runtime readers are not visible enough through
# Sorbet's generic Data RBI. These mirror the hand-written RBS surfaces.
module Rush
  module AST
    class Assignment < Data
      sig { returns(String) }
      attr_reader :name

      sig { returns(Word) }
      attr_reader :value

      sig { params(name: String, value: Word).returns(Assignment) }
      def self.new(name:, value:); end
    end

    class Redirect < Data
      sig { returns(Symbol) }
      attr_reader :kind

      sig { returns(T.untyped) }
      attr_reader :target

      sig { returns(T.nilable(Integer)) }
      attr_reader :io_number

      sig { params(kind: Symbol, target: T.untyped, io_number: T.nilable(Integer)).returns(Redirect) }
      def self.new(kind:, target:, io_number:); end

      sig do
        params(kind: T.nilable(Symbol), target: T.untyped, io_number: T.nilable(Integer))
          .returns(Redirect)
      end
      def with(kind: nil, target: nil, io_number: nil); end
    end

    class ParamRef < Data
      sig { returns(String) }
      attr_reader :name

      sig { returns(T.nilable(String)) }
      attr_reader :op

      sig { returns(T.nilable(String)) }
      attr_reader :arg

      sig { params(name: String, op: T.nilable(String), arg: T.nilable(String)).returns(ParamRef) }
      def self.new(name:, op:, arg:); end
    end

    class ListEntry < Data
      sig { returns(Node) }
      attr_reader :and_or

      sig { returns(T::Boolean) }
      attr_reader :async

      sig { params(and_or: Node, async: T::Boolean).returns(ListEntry) }
      def self.new(and_or:, async:); end
    end

    class CaseItem < Data
      sig { returns(T::Array[Word]) }
      attr_reader :patterns

      sig { returns(Node) }
      attr_reader :body

      sig { params(patterns: T::Array[Word], body: Node).returns(CaseItem) }
      def self.new(patterns:, body:); end
    end
  end
end
