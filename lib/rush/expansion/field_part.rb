# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # One expanded fragment on its way to field splitting, as
    # [text, splittable, break, quoted]: the text itself, whether IFS may split
    # it, whether a new field opens before it regardless of IFS (the boundary
    # between $@/$* elements), and whether glob metacharacters need shielding.
    FieldPart = T.type_alias { [String, T::Boolean, T::Boolean, T::Boolean] }
  end
end
