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

      sig { params(name: String, klass: T.class_of(Base)).void }
      def register(name, klass)
        @builtins[name] = klass
      end

      sig { params(name: String).returns(T.class_of(Base)) }
      def fetch(name)
        @builtins.fetch(name)
      end

      sig { params(name: T.nilable(String)).returns(T.nilable(T.class_of(Base))) }
      def lookup(name)
        return unless name

        @builtins.fetch(name, nil)
      end

      sig { params(name: T.nilable(String)).returns(T::Boolean) }
      def key?(name)
        !!(name && @builtins.key?(name))
      end
    end
  end
end
