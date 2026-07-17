# typed: true
# frozen_string_literal: true

# Data.define readers and constructors that Sorbet's generic Data RBI cannot
# recover. These mirror the independent RBS value contracts.
module Rush
  module Builtins
    # Immutable resource metadata for ulimit.
    class UlimitResource < Data
      extend T::Sig

      sig { returns(String) }
      attr_reader :flag

      sig { returns(String) }
      attr_reader :label

      sig { returns(Symbol) }
      attr_reader :resource

      sig { returns(Integer) }
      attr_reader :scale

      sig do
        params(flag: String, label: String, resource: Symbol, scale: Integer).returns(UlimitResource)
      end
      def self.new(flag, label, resource, scale); end
    end

    # Parsed ulimit request value.
    class UlimitRequest < Data
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_reader :all

      sig { returns(UlimitResource) }
      attr_reader :resource

      sig { returns(Symbol) }
      attr_reader :target

      sig { returns(T::Boolean) }
      attr_reader :explicit_target

      sig { returns(T.nilable(String)) }
      attr_reader :value

      sig do
        params(all: T::Boolean, resource: UlimitResource, target: Symbol,
               explicit_target: T::Boolean, value: T.nilable(String)).returns(UlimitRequest)
      end
      # rubocop:disable Metrics/ParameterLists -- mirrors the positional Data constructor
      def self.new(all, resource, target, explicit_target, value); end
      # rubocop:enable Metrics/ParameterLists
    end

    # Parsed ulimit error value.
    class UlimitParseError < Data
      extend T::Sig

      sig { returns(Symbol) }
      attr_reader :kind

      sig { returns(T.nilable(String)) }
      attr_reader :detail

      sig { params(kind: Symbol, detail: T.nilable(String)).returns(UlimitParseError) }
      def self.new(kind, detail); end
    end
  end
end
