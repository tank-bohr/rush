# typed: true
# frozen_string_literal: true

module Rush
  # Finds the outer close of a shell bracket expression without mistaking the
  # `]` inside POSIX `[:class:]`, `[=equiv=]` or `[.collating.]` for it.
  class BracketScanner
    extend T::Sig

    TOKEN_ENDS = T.let({ ':' => ':]', '=' => '=]', '.' => '.]' }.freeze, T::Hash[String, String])

    sig { params(pattern: String, start: Integer).void }
    def initialize(pattern, start)
      @pattern = pattern
      @index = first_index(start)
      @special = false
    end

    sig { returns([T.nilable(Integer), T::Boolean]) }
    def call
      advance until complete?
      [finish, special]
    end

    private

    sig { returns(String) }
    attr_reader :pattern

    sig { returns(Integer) }
    attr_accessor :index

    sig { returns(T::Boolean) }
    attr_accessor :special

    sig { params(start: Integer).returns(Integer) }
    def first_index(start)
      index = start + 1
      index += 1 if %w[! ^].include?(pattern[index])
      pattern[index] == ']' ? index + 1 : index
    end

    sig { returns(T::Boolean) }
    def complete?
      current = pattern[index]
      !current || current == ']'
    end

    sig { void }
    def advance
      token_finish = nested_finish
      self.special = true if token_finish
      self.index = token_finish || escaped_finish || (index + 1)
    end

    sig { returns(T.nilable(Integer)) }
    def escaped_finish
      index + 2 if pattern[index] == '\\' && pattern[index + 1]
    end

    sig { returns(T.nilable(Integer)) }
    def nested_finish
      cursor = index
      ending = nested_ending(cursor)
      found = pattern.index(ending, cursor + 2) if ending
      found + 2 if found
    end

    sig { params(cursor: Integer).returns(T.nilable(String)) }
    def nested_ending(cursor)
      TOKEN_ENDS[pattern[cursor + 1].to_s] if pattern[cursor] == '['
    end

    sig { returns(T.nilable(Integer)) }
    def finish
      index + 1 if index < pattern.length
    end
  end
end
