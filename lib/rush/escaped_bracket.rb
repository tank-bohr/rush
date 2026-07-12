# typed: true
# frozen_string_literal: true

module Rush
  # Converts shell-backslash-quoted bracket members to positions where a POSIX
  # ERE bracket treats them literally. Kept separate from PosixPattern because
  # this is a small stateful bracket normalization, not scanner policy.
  class EscapedBracket
    extend T::Sig

    SPECIAL = [']', '-', '^', '['].freeze

    sig { params(source: String).void }
    def initialize(source)
      @negated = source.start_with?('[^')
      @body = T.must(source[(@negated ? 2 : 1)...-1])
      @literals = T.let(
        {}, #: Hash[String, String]
        T::Hash[String, String]
      )
      SPECIAL.each { |char| extract(char) }
    end

    sig { returns(String) }
    def source
      body = @body.gsub(/\\(.)/m, '\\1')
      "#{prefix}#{literal(']')}#{body}#{literal('^')}#{literal('[')}#{literal('-')}]"
    end

    private

    sig { returns(String) }
    def prefix
      @negated ? '[^' : '['
    end

    sig { params(char: String).returns(String) }
    def literal(char)
      @literals.fetch(char, '')
    end

    sig { params(char: String).void }
    def extract(char)
      escaped = "\\#{char}"
      @literals[char] = char if @body.include?(escaped)
      @body = @body.gsub(escaped, '')
    end
  end
end
