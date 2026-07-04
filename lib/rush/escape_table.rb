# typed: true
# frozen_string_literal: true

module Rush
  # Renders backslash escapes from a small table. Missing trailing characters
  # become a literal backslash; unknown escapes keep the backslash plus character.
  class EscapeTable
    extend T::Sig

    sig { params(table: T::Hash[String, String]).void }
    def initialize(table)
      @table = table
    end

    sig { params(char: T.nilable(String)).returns(String) }
    def escape(char)
      return '\\' unless char

      @table.fetch(char) { "\\#{char}" }
    end
  end
end
