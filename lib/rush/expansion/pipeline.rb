# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. Each segment expands to one
    # or more parts ([text, splittable, break_before]); unquoted results undergo
    # IFS field splitting and then pathname expansion. The one multi-field case is
    # "$@"/$@, which yields one part per positional parameter with a forced field
    # break between them ($* always joins to a scalar). Quoted metacharacters are
    # backslash-escaped so they survive field splitting and glob literally.
    class Pipeline
      def initialize(executor)
        @executor = executor
      end

      # Argv expansion: expand each word to fields (splitting unquoted on IFS),
      # then expand each field's pathname patterns.
      def expand(words) = words.flat_map { |word| glob(FieldSplitter.new(ifs).split(parts(word))) }

      # Assignment RHS / redirection target / operator word: one field, no split.
      # Tilde expands at the leading position by default; assignment context also
      # expands after colons, and arithmetic opts out (~ is bitwise not there).
      def expand_value(word, tilde: :leading)
        tilde_expand(word.segments, tilde).map { |segment| scalar_segment(segment) }.join
      end

      private

      def parts(word) = tilde_expand(word.segments, :leading).flat_map { |segment| field_parts(segment) }

      def tilde_expand(segments, mode)
        return segments if mode == :none

        TildeExpander.new(@executor).expand(segments, assignment: mode == :assignment)
      end

      def glob(fields) = fields.flat_map { |field| GlobExpander.new(@executor).expand(field) }

      def field_parts(segment)
        return splat_parts(segment) if splat?(segment)

        [[escape(scalar_segment(segment), segment.quoted), splittable?(segment), false]]
      end

      # Backslash-escape glob metacharacters that came from quoted text so they
      # match literally; unquoted text keeps them active.
      def escape(text, quoted) = quoted ? text.gsub(/[\\*?\[]/) { |meta| "\\#{meta}" } : text

      def splat?(segment)
        return false unless segment.kind == :param && segment.value.op.nil?

        segment.value.name == '@' || (segment.value.name == '*' && !segment.quoted)
      end

      def splat_parts(segment)
        split = !segment.quoted
        @executor.state.positional.map.with_index do |element, index|
          [escape(element, segment.quoted), split, index.positive?]
        end
      end

      def splittable?(segment) = segment.kind != :literal && !segment.quoted

      def ifs = @executor.state.environment.get('IFS')

      def scalar_segment(segment)
        return segment.value if segment.kind == :literal
        return ParameterExpander.new(@executor, segment.value).expand if segment.kind == :param
        return ArithmeticExpander.new(@executor, segment.value).expand if segment.kind == :arith

        CommandSubstitution.new(@executor, segment.value).call
      end
    end
  end
end
