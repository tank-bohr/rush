# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. Each segment expands to one
    # or more parts ([text, splittable, break_before]); unquoted results undergo
    # IFS field splitting. The one multi-field case is "$@"/$@, which yields one
    # part per positional parameter with a forced field break between them ($*
    # always joins to a scalar, so it needs no special handling). Pathname
    # expansion (globbing) arrives in a later phase.
    class Pipeline
      def initialize(executor)
        @executor = executor
      end

      # Argv expansion: expand each word to fields, splitting unquoted on IFS.
      def expand(words) = words.flat_map { |word| FieldSplitter.new(ifs).split(parts(word)) }

      # Assignment RHS / redirection target / operator word: one field, no split.
      def expand_value(word) = word.segments.map { |segment| scalar_segment(segment) }.join

      private

      def parts(word) = word.segments.flat_map { |segment| field_parts(segment) }

      def field_parts(segment)
        return splat_parts(segment) if splat?(segment)

        [[scalar_segment(segment), splittable?(segment), false]]
      end

      def splat?(segment)
        return false unless segment.kind == :param && segment.value.op.nil?

        segment.value.name == '@' || (segment.value.name == '*' && !segment.quoted)
      end

      def splat_parts(segment)
        split = !segment.quoted
        @executor.state.positional.map.with_index { |element, index| [element, split, index.positive?] }
      end

      def splittable?(segment) = segment.kind != :literal && !segment.quoted

      def ifs = @executor.state.environment.get('IFS')

      def scalar_segment(segment)
        case segment.kind
        when :literal then segment.value
        when :param then ParameterExpander.new(@executor, segment.value).expand
        else CommandSubstitution.new(@executor, segment.value).call
        end
      end
    end
  end
end
