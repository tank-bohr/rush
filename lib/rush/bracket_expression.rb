# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  # One shell-pattern bracket expression. It recognizes the nested POSIX
  # character-class, equivalence-class and collating-symbol delimiters so their
  # inner `]` does not terminate the outer expression.
  class BracketExpression
    extend T::Sig

    CLASS_NAMES = %w[alnum alpha blank cntrl digit graph lower print punct space upper xdigit].freeze

    sig { returns(String) }
    attr_reader :source

    sig { returns(Integer) }
    attr_reader :finish

    sig { params(pattern: String, start: Integer).returns(T.nilable(BracketExpression)) }
    def self.parse(pattern, start)
      finish, special = BracketScanner.new(pattern, start).call
      return new(T.must(pattern[start...finish]), finish, special, true) if finish

      new(T.must(pattern[start..]), pattern.length, true, false) if special
    end

    sig { params(source: String, finish: Integer, special: T::Boolean, closed: T::Boolean).void }
    def initialize(source, finish, special, closed)
      @source = source
      @finish = finish
      @special = special
      @closed = closed
    end

    sig { returns(T::Boolean) }
    def special?
      @special
    end

    sig { returns(String) }
    def glob_source
      special? ? '?' : source
    end

    sig { params(regexp: String, glob: String, scanner: StringScanner).void }
    def append_to(regexp, glob, scanner)
      regexp << regex
      glob << glob_source
      scanner.pos = finish
    end

    # Ruby regexp supports the twelve required POSIX named classes. The two
    # collation forms have a portable one-character meaning in the POSIX locale;
    # multi-character locale collation is deliberately left invalid here.
    sig { returns(String) }
    def regex
      raise RegexpError unless @closed

      "[#{regexp_body}]"
    rescue RegexpError
      '(?!)'
    end

    private

    sig { returns(String) }
    def regexp_body
      body = collating(classes(negation(source.delete_prefix('[').delete_suffix(']'))))
      escape_brackets(body)
    end

    sig { params(body: String).returns(String) }
    def escape_brackets(body)
      body = body.sub(/\A(\^?)\]/) { "#{Regexp.last_match(1)}\\]" }
      body.gsub(/(?<!\\)\[(?!:)/, '\\\\[')
    end

    sig { params(body: String).returns(String) }
    def negation(body)
      body.sub(/\A[!^]/, '^')
    end

    sig { params(body: String).returns(String) }
    def classes(body)
      body.gsub(/\[:([a-z]+):\]/) do
        name = Regexp.last_match(1)
        raise RegexpError unless CLASS_NAMES.include?(name)

        "[:#{name}:]"
      end
    end

    sig { params(body: String).returns(String) }
    def collating(body)
      body.gsub(/\[([=.])(.*?)\1\]/) { collating_element(T.must(Regexp.last_match(2))) }
    end

    sig { params(element: String).returns(String) }
    def collating_element(element)
      raise RegexpError unless element.each_char.one?

      Regexp.escape(element)
    end
  end
end
