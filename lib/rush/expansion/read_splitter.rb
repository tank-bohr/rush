# frozen_string_literal: true

module Rush
  module Expansion
    # Field splitting for the `read` builtin: strip leading IFS whitespace, split
    # into at most `count` fields (the last keeps the unsplit remainder, with
    # trailing IFS whitespace removed) and pad with empty strings up to `count`.
    # Default whitespace IFS only; the full IFS rules arrive with Phase 2.
    class ReadSplitter
      DEFAULT_IFS = " \t\n"

      def initialize(ifs, count)
        @ifs = ifs || DEFAULT_IFS
        @count = count
      end

      def split(line)
        return pad([line]) if @ifs.empty?

        pad(trim_last(strip_leading(line).split(pattern, @count)))
      end

      private

      def strip_leading(line) = line.sub(/\A#{pattern}/, '')

      def trim_last(fields)
        fields[-1] = fields[-1].sub(/#{pattern}\z/, '') unless fields.empty?
        fields
      end

      def pad(fields) = fields + ([''] * (@count - fields.size))

      def pattern = /(?:#{Regexp.union(@ifs.chars.uniq).source})+/
    end
  end
end
