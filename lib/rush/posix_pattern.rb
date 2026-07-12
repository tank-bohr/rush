# typed: true
# frozen_string_literal: true

module Rush
  # Translates one shell pattern into a POSIX extended regular expression. The
  # libc regex engine then supplies LC_COLLATE equivalence classes, collating
  # symbols and locale ranges that Ruby's regexp/fnmatch APIs do not expose.
  # :reek:InstanceVariableAssumption -- @scanner is initialized by PatternScanner#initialize
  class PosixPattern < PatternScanner
    extend T::Sig

    ERE_SPECIAL = /[.\^$+(){}|\[\]*?\\]/
    RUBY_GLOB_SPECIAL = %w[{ }].freeze

    sig { returns(String) }
    attr_reader :source, :glob_source

    sig { params(pattern: String).void }
    def initialize(pattern)
      @source = +'^'
      @glob_source = +''
      super
      @source << '$'
    end

    private

    sig { void }
    def append_escape
      @scanner.getch
      escaped = @scanner.getch || '\\'
      @glob_source << '\\' << escaped
      append_ere_literal(escaped)
    end

    sig { void }
    def append_wildcard
      char = @scanner.getch.to_s
      append_discovery(char)
      @source << (char == '*' ? '.*' : '.')
    end

    sig { void }
    def append_bracket
      bracket = BracketExpression.parse(@scanner.string, @scanner.pos)
      return append_literal unless bracket

      @source << bracket_source(bracket)
      append_discovery('*')
      @scanner.pos = bracket.finish
    end

    sig { params(bracket: BracketExpression).returns(String) }
    def bracket_source(bracket)
      source = bracket.source.sub(/\A\[!/, '[^')
      source.include?('\\') ? EscapedBracket.new(source).source : source
    end

    sig { void }
    def append_literal
      char = @scanner.getch.to_s
      append_discovery(char)
      append_ere_literal(char)
    end

    sig { params(char: String).void }
    def append_discovery(char)
      return if char == '*' && @glob_source.end_with?('*')

      @glob_source << (RUBY_GLOB_SPECIAL.include?(char) ? "\\#{char}" : char)
    end

    sig { params(char: String).void }
    def append_ere_literal(char)
      @source << (char.match?(ERE_SPECIAL) ? "\\#{char}" : char)
    end
  end
end
