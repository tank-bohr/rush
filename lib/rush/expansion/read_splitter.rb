# frozen_string_literal: true

module Rush
  module Expansion
    # Field splitting for the `read` builtin: strip leading IFS whitespace, split
    # into at most `count` fields (the last keeps the unsplit remainder, with
    # trailing IFS whitespace removed) and pad with empty strings up to `count`.
    # Uses the full three IFS cases: whitespace coalesces, each non-whitespace
    # IFS character delimits (generating empty fields), null IFS does not split.
    class ReadSplitter
      WHITESPACE = " \t\n"

      def initialize(ifs, count)
        @ifs = ifs
        @count = count
        @chars = (ifs || WHITESPACE).chars.uniq
      end

      def split(line)
        return pad([line]) if @ifs == ''

        pad(trim_last(line.sub(leading, '').split(delimiter, @count)))
      end

      private

      def whitespace = @chars.select { |char| WHITESPACE.include?(char) }

      def others = @chars.reject { |char| WHITESPACE.include?(char) }

      # A field delimiter: one non-whitespace IFS char with any adjacent IFS
      # whitespace, or a run of IFS whitespace on its own.
      def delimiter = Regexp.new("#{ws}*(?:#{Regexp.union(others).source})#{ws}*|#{ws}+")

      def leading = /\A#{ws}+/

      def trim_last(fields)
        fields[-1] = fields[-1].sub(/#{ws}+\z/, '') unless fields.empty?
        fields
      end

      def ws = "(?:#{Regexp.union(whitespace).source})"

      def pad(fields) = fields + ([''] * (@count - fields.size))
    end
  end
end
