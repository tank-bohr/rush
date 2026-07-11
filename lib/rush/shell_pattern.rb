# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  # A shell `case`/parameter/pathname pattern. Ruby handles ordinary patterns;
  # patterns containing POSIX bracket subforms are compiled to a Ruby regexp,
  # while #glob_source broadens those brackets for Dir.glob candidate discovery.
  class ShellPattern
    extend T::Sig

    sig { returns(String) }
    attr_reader :glob_source

    sig { params(source: String).void }
    def initialize(source)
      @scanner = StringScanner.new(source)
      @regexp = +''
      @glob_source = +''
      @extended = false
      compile
    end

    sig { returns(T::Boolean) }
    def extended?
      @extended
    end

    sig { params(text: String).returns(T::Boolean) }
    def match?(text)
      return File.fnmatch(@scanner.string, text, File::FNM_DOTMATCH) unless extended?

      Regexp.new("\\A#{@regexp}\\z", Regexp::MULTILINE).match?(text)
    rescue RegexpError
      false
    end

    sig { params(text: String).returns(T::Boolean) }
    def ===(text)
      match?(text)
    end

    private

    sig { void }
    def compile
      step until @scanner.eos?
    end

    sig { void }
    def step
      return append_escape if current == '\\'
      return append_wildcard if %w[* ?].include?(current)
      return append_bracket if current == '['

      append_literal
    end

    sig { returns(String) }
    def current
      @scanner.peek(1)
    end

    sig { void }
    def append_escape
      @scanner.getch
      escaped = @scanner.getch
      @glob_source << '\\' << escaped.to_s
      @regexp << Regexp.escape(escaped || '\\')
    end

    sig { void }
    def append_wildcard
      char = @scanner.getch.to_s
      @glob_source << char
      @regexp << (char == '*' ? '.*' : '.')
    end

    sig { void }
    def append_bracket
      bracket = BracketExpression.parse(@scanner.string, @scanner.pos)
      return append_literal unless bracket

      append_expression(bracket)
    end

    sig { params(bracket: BracketExpression).void }
    def append_expression(bracket)
      bracket.append_to(@regexp, @glob_source, @scanner)
      @extended = bracket.special? || @extended
    end

    sig { void }
    def append_literal
      char = @scanner.getch.to_s
      @glob_source << char
      @regexp << Regexp.escape(char)
    end
  end
end
