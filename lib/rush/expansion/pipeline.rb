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
      # Each word-segment kind expands through its own (executor, value) -> #expand
      # strategy; :literal uses the identity expander so the dispatch is uniform.
      EXPANDERS = { literal: Literal, param: ParameterExpander,
                    arith: ArithmeticExpander, command: CommandSubstitution }.freeze

      # Tilde expansion strategy per mode (operates on a word's segment list).
      GROUP_EXPANDERS = { none: NoTilde, leading: TildeExpander, assignment: AssignmentTilde }.freeze

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
        GROUP_EXPANDERS.fetch(mode).new(@executor).expand(segments)
      end

      def glob(fields) = fields.flat_map { |field| GlobExpander.new(@executor).expand(field) }

      def field_parts(segment)
        return splat_parts(segment) if splat?(segment)

        text = scalar_segment(segment)
        # Quoted text escapes its glob metacharacters so they match literally;
        # unquoted text keeps them active.
        [[segment.quoted ? escape(text) : text, splittable?(segment), false]]
      end

      def escape(text) = text.gsub(/[\\*?\[]/) { |meta| "\\#{meta}" }

      def splat?(segment)
        value = segment.value
        return false unless segment.kind == :param && !value.op

        value.name == '@' || (value.name == '*' && !segment.quoted)
      end

      def splat_parts(segment)
        split = !segment.quoted
        @executor.state.positional.map.with_index do |element, index|
          [segment.quoted ? escape(element) : element, split, index.positive?]
        end
      end

      def splittable?(segment) = segment.kind != :literal && !segment.quoted

      def ifs = @executor.state.environment.get('IFS')

      def scalar_segment(segment)
        EXPANDERS.fetch(segment.kind).new(@executor, segment.value).expand
      end
    end
  end
end
