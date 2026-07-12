# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  # Shared left-to-right shell-pattern scanner. Concrete compilers implement
  # the four append_* handlers; this class owns token dispatch and cursor
  # progress so the Ruby fallback and native ERE translator cannot drift.
  class PatternScanner
    extend T::Sig

    HANDLERS = { '\\' => :append_escape, '*' => :append_wildcard,
                 '?' => :append_wildcard, '[' => :append_bracket }.freeze

    sig { params(pattern: String).void }
    def initialize(pattern)
      @scanner = StringScanner.new(pattern)
      scan
    end

    private

    sig { void }
    def scan
      step until @scanner.eos?
    end

    sig { void }
    def step
      handler = HANDLERS.fetch(@scanner.peek(1), :append_literal)
      send(handler)
    end
  end
end
