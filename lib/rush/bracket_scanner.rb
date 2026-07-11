# typed: true
# frozen_string_literal: true

module Rush
  # Finds the outer close of a shell bracket expression without mistaking the
  # `]` inside POSIX `[:class:]`, `[=equiv=]` or `[.collating.]` for it.
  class BracketScanner
    extend T::Sig

    TOKEN_ENDS = { ':' => ':]', '=' => '=]', '.' => '.]' }.freeze

    sig { params(pattern: String, start: Integer).void }
    def initialize(pattern, start)
      @pattern = pattern
      @index = first_index(start)
      @special = false
    end

    sig { returns([T.nilable(Integer), T::Boolean]) }
    def call
      advance until complete?
      [finish, @special]
    end

    private

    sig { params(start: Integer).returns(Integer) }
    def first_index(start)
      index = start + 1
      index += 1 if %w[! ^].include?(@pattern[index])
      @pattern[index] == ']' ? index + 1 : index
    end

    sig { returns(T::Boolean) }
    def complete?
      current = @pattern[@index]
      !current || current == ']'
    end

    sig { void }
    def advance
      token_finish = nested_finish
      @special = true if token_finish
      @index = token_finish || escaped_finish || (@index + 1)
    end

    sig { returns(T.nilable(Integer)) }
    def escaped_finish
      @index + 2 if @pattern[@index] == '\\' && @pattern[@index + 1]
    end

    sig { returns(T.nilable(Integer)) }
    def nested_finish
      ending = TOKEN_ENDS[@pattern[@index + 1].to_s] if @pattern[@index] == '['
      found = @pattern.index(ending, @index + 2) if ending
      found + 2 if found
    end

    sig { returns(T.nilable(Integer)) }
    def finish
      @index + 1 if @index < @pattern.length
    end
  end
end
