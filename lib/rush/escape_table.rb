# typed: true
# frozen_string_literal: true

module Rush
  # Renders a backslash escape from a small table. Missing trailing characters
  # become a literal backslash; unknown escapes keep the backslash plus character.
  module EscapeTable
    extend T::Sig

    module_function

    sig { params(char: T.nilable(String), table: T::Hash[String, String]).returns(String) }
    def render(char, table)
      return '\\' unless char

      table.fetch(char) { "\\#{char}" }
    end
  end
end
