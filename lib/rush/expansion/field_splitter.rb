# frozen_string_literal: true

module Rush
  module Expansion
    # Splits a word's expanded parts into fields on IFS. Each part is [text,
    # splittable]; only splittable parts (results of unquoted expansion) are
    # split. A field is kept if it is non-empty or has a literal/quoted part, so
    # empty unquoted expansions vanish while "" survives. Slice 2c implements the
    # default whitespace IFS (runs collapse, empties drop); the full non-
    # whitespace three-case behaviour arrives in Phase 2.
    class FieldSplitter
      DEFAULT_IFS = " \t\n"

      def initialize(ifs)
        @ifs = ifs || DEFAULT_IFS
      end

      def split(parts)
        fields = [[+'', false]]
        parts.each { |text, splittable| add(fields, text, splittable) }
        fields.select { |text, real| real || !text.empty? }.map(&:first)
      end

      private

      def add(fields, text, splittable)
        splittable ? split_part(fields, text) : keep(fields, text)
      end

      def keep(fields, text)
        fields.last[0] << text
        fields.last[1] = true
      end

      def split_part(fields, text)
        tokens = text.split(pattern, -1)
        return if tokens.empty? # empty unquoted expansion contributes no field

        fields.last[0] << tokens.first
        tokens.drop(1).each { |token| fields << [token, false] }
      end

      def pattern = @ifs.empty? ? /(?!)/ : /(?:#{Regexp.union(@ifs.chars.uniq).source})+/
    end
  end
end
