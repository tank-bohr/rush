# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # One expanded fragment on its way to field splitting, as
    # [text, splittable, break]: the text itself, whether IFS may split it
    # (unquoted origin), and whether a new field opens before it regardless
    # of IFS (the boundary between $@/$* elements).
    FieldPart = T.type_alias { [String, T::Boolean, T::Boolean] }
  end
end
