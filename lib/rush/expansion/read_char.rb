# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # One annotated character of a line consumed by the `read` builtin, as
    # [char, escaped]: the character itself and whether a backslash escaped it
    # (an escaped character keeps its literal value and never acts as an IFS
    # delimiter). A zero-width joint (['', true]) marks where a backslash-newline
    # continuation joined two physical lines.
    ReadChar = T.type_alias { [String, T::Boolean] }
  end
end
