# frozen_string_literal: true

module Rush
  module Builtins
    # O(1) name -> builtin class lookup, populated by Builtins.default_registry.
    class Registry
      def initialize
        @builtins = {}
      end

      def register(name, klass)
        @builtins[name] = klass
      end

      def fetch(name)
        @builtins[name]
      end

      def key?(name)
        @builtins.key?(name)
      end
    end
  end
end
