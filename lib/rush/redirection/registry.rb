# typed: true
# frozen_string_literal: true

module Rush
  # I/O redirection: the per-kind appliers and the registry that dispatches to them.
  module Redirection
    extend T::Sig

    # O(1) redirection-kind -> applier lookup, populated by default_registry.
    class Registry
      extend T::Sig

      sig { void }
      def initialize
        @appliers = {}
      end

      sig { params(kind: Symbol, applier: T.untyped).void }
      def register(kind, applier)
        @appliers[kind] = applier
      end

      sig { params(kind: Symbol).returns(T.untyped) }
      def fetch(kind)
        @appliers.fetch(kind)
      end
    end

    # <> opens read-write and creates the file (POSIX), unlike the string modes.
    DEFAULTS = {
      in: ['r', 0, nil], out: ['w', 1, :noclobber], append: ['a', 1, nil],
      readwrite: [File::RDWR | File::CREAT, 0, nil], clobber: ['w', 1, nil]
    }.freeze

    # Default fd for the dup operators: 1 for >&, 0 for <&.
    DUPS = { dup_out: 1, dup_in: 0 }.freeze

    sig { params(options: T.nilable(Options)).returns(Registry) }
    def self.default_registry(options = nil)
      Registry.new.tap do |registry|
        DEFAULTS.each { |kind, spec| register_file(registry, kind, spec, options) }
        DUPS.each { |kind, fd| registry.register(kind, DupRedirect.new(fd)) }
        registry.register(:heredoc, HereDocRedirect.new)
      end
    end

    sig { params(registry: Registry, kind: Symbol, spec: T::Array[T.untyped], options: T.nilable(Options)).void }
    def self.register_file(registry, kind, spec, options)
      redirect = FileRedirect.new(spec.fetch(0), spec.fetch(1), options: options, protection: spec.fetch(2))
      registry.register(kind, redirect)
    end
  end
end
