# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # O(1) name -> builtin class lookup, populated by Builtins.default_registry.
    class Registry
      extend T::Sig

      sig { void }
      def initialize
        @builtins = {}
      end

      sig { params(name: T.untyped, klass: T.untyped).returns(T.untyped) }
      def register(name, klass)
        @builtins[name] = klass
      end

      sig { params(name: T.untyped).returns(T.untyped) }
      def fetch(name)
        @builtins[name]
      end

      sig { params(name: T.untyped).returns(T.untyped) }
      def key?(name)
        @builtins.key?(name)
      end
    end
  end
end
