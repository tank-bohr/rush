# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. Each segment expands itself
    # to one or more parts ([text, splittable, break_before]); unquoted results
    # undergo IFS field splitting and then pathname expansion. The one multi-field
    # case is "$@"/$@, which yields one part per positional parameter with a
    # forced field break between them ($* always joins to a scalar). Quoted
    # metacharacters are backslash-escaped so they survive splitting and glob.
    class Pipeline
      # Tilde expansion strategy per mode (its value is a word's segment list).
      TILDE_EXPANDERS = { none: NoTilde, leading: TildeExpander, assignment: AssignmentTilde }.freeze

      def initialize(executor)
        @executor = executor
      end

      # Argv expansion: expand each word to fields (splitting unquoted on IFS),
      # then expand each field's pathname patterns.
      def expand(words)
        words.flat_map { |word| glob(FieldSplitter.new(ifs).split(parts(word))) }
      end

      # Assignment RHS / redirection target / operator word: one field, no split.
      # Tilde expands at the leading position by default; assignment context also
      # expands after colons, and arithmetic opts out (~ is bitwise not there).
      def expand_value(word, tilde: :leading)
        tilde_expand(word.segments, tilde).map { |segment| segment.expand(@executor) }.join
      end

      private

      def parts(word)
        tilde_expand(word.segments, :leading).flat_map { |segment| field_parts(segment) }
      end

      def tilde_expand(segments, mode)
        TILDE_EXPANDERS.fetch(mode).new(@executor, segments).expand
      end

      def glob(fields)
        fields.flat_map { |field| GlobExpander.new(@executor).expand(field) }
      end

      def field_parts(segment)
        return splat_parts(segment) if segment.splat?

        [[escape_if_quoted(segment, segment.expand(@executor)), segment.splittable?, false]]
      end

      # Glob metacharacters in quoted text are escaped so they match literally;
      # unquoted text keeps them active.
      def escape_if_quoted(segment, text)
        segment.quoted ? escape(text) : text
      end

      def escape(text)
        text.gsub(/[\\*?\[]/) { |meta| "\\#{meta}" }
      end

      def splat_parts(segment)
        split = !segment.quoted
        @executor.state.positional.map.with_index do |element, index|
          [escape_if_quoted(segment, element), split, index.positive?]
        end
      end

      def ifs
        @executor.state.environment.get('IFS')
      end
    end
  end
end
