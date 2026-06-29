# typed: true
# frozen_string_literal: true

module Rush
  # I/O redirection: the per-kind appliers and the registry that dispatches to them.
  module Redirection
    # O(1) redirection-kind -> applier lookup, populated by default_registry.
    class Registry
      def initialize
        @appliers = {}
      end

      def register(kind, applier)
        @appliers[kind] = applier
      end

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

    def self.default_registry
      Registry.new.tap do |registry|
        DEFAULTS.each { |kind, spec| registry.register(kind, FileRedirect.new(spec[0], spec[1])) }
        DUPS.each { |kind, fd| registry.register(kind, DupRedirect.new(fd)) }
        registry.register(:heredoc, HereDocRedirect.new)
      end
    end
  end
end
