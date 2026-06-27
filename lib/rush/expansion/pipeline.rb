# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. Each word's segments are
    # expanded (literal -> value, :param -> parameter expansion, :command ->
    # command substitution), then unquoted results undergo field splitting on
    # IFS. Pathname expansion (globbing) and quote removal beyond the scanner's
    # arrive in later slices.
    class Pipeline
      def initialize(executor)
        @executor = executor
      end

      # Argv expansion: expand each word, then split unquoted results into fields.
      def expand(words) = words.flat_map { |word| FieldSplitter.new(ifs).split(parts(word)) }

      # Assignment RHS / redirection target / operator word: a single field, no split.
      def expand_value(word) = word.segments.map { |segment| expand_segment(segment) }.join

      private

      def parts(word) = word.segments.map { |segment| [expand_segment(segment), splittable?(segment)] }

      def splittable?(segment) = segment.kind != :literal && !segment.quoted

      def ifs = @executor.state.environment.get('IFS')

      def expand_segment(segment)
        case segment.kind
        when :literal then segment.value
        when :param then ParameterExpander.new(@executor, segment.value).expand
        else CommandSubstitution.new(@executor, segment.value).call
        end
      end
    end
  end
end
