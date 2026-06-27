# frozen_string_literal: true

module Rush
  module Redirection
    # O(1) redirection-kind -> applier lookup, populated by default_registry.
    class Registry
      def initialize = @appliers = {}

      def register(kind, applier) = @appliers[kind] = applier

      def fetch(kind) = @appliers[kind]
    end

    # <> opens read-write and creates the file (POSIX), unlike the string modes.
    DEFAULTS = {
      in: ['r', 0], out: ['w', 1], append: ['a', 1],
      readwrite: [File::RDWR | File::CREAT, 0], clobber: ['w', 1]
    }.freeze

    def self.default_registry
      Registry.new.tap do |registry|
        DEFAULTS.each { |kind, (mode, fd)| registry.register(kind, FileRedirect.new(mode, fd)) }
        registry.register(:heredoc, HereDocRedirect.new)
      end
    end
  end
end
