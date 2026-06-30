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
        @appliers[kind]
      end
    end

    # <> opens read-write and creates the file (POSIX), unlike the string modes.
    DEFAULTS = {
      in: ['r', 0], out: ['w', 1], append: ['a', 1],
      readwrite: [File::RDWR | File::CREAT, 0], clobber: ['w', 1]
    }.freeze

    # Default fd for the dup operators: 1 for >&, 0 for <&.
    DUPS = { dup_out: 1, dup_in: 0 }.freeze

    sig { returns(Registry) }
    def self.default_registry
      Registry.new.tap do |registry|
        DEFAULTS.each { |kind, spec| registry.register(kind, FileRedirect.new(spec[0], spec[1])) }
        DUPS.each { |kind, fd| registry.register(kind, DupRedirect.new(fd)) }
        registry.register(:heredoc, HereDocRedirect.new)
      end
    end
  end
end
