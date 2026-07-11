# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. Each segment expands itself
    # to one or more parts ([text, splittable, break_before, quoted]); unquoted results
    # undergo IFS field splitting and then pathname expansion. The one multi-field
    # case is "$@"/$@, which yields one part per positional parameter with a
    # forced field break between them ($* always joins to a scalar). Quoted
    # metacharacters are backslash-escaped so they survive splitting and glob.
    class Pipeline
      extend T::Sig

      # Tilde expansion strategy per mode (its value is a word's segment list).
      TILDE_EXPANDERS = { none: NoTilde, leading: TildeExpander, assignment: AssignmentTilde }.freeze

      sig { params(executor: Executor).void }
      def initialize(executor)
        @executor = executor
      end

      # Argv expansion: expand each word to fields (splitting unquoted on IFS),
      # then expand each field's pathname patterns.
      sig { params(words: T::Array[AST::Word]).returns(T::Array[String]) }
      def expand(words)
        words.flat_map { |word| glob(FieldSplitter.new(ifs).split(parts(word))) }
      end

      # Assignment RHS / redirection target / operator word: one field, no split.
      # Tilde expands at the leading position by default; assignment context also
      # expands after colons, and arithmetic opts out (~ is bitwise not there).
      sig { params(word: T.any(AST::Word, HereDoc), tilde: Symbol).returns(String) }
      def expand_value(word, tilde: :leading)
        collapse(expand_parts(word, tilde: tilde))
      end

      # Expand without splitting or globbing while retaining each segment's
      # quote provenance for a surrounding ${...} operator word.
      sig { params(word: T.any(AST::Word, HereDoc), tilde: Symbol).returns(T::Array[FieldPart]) }
      def expand_parts(word, tilde: :leading)
        tilde_expand(word.segments, tilde).flat_map { |segment| field_parts(segment) }
      end

      sig { params(expanded: T::Array[FieldPart]).returns(String) }
      def collapse(expanded)
        separator = field_separator
        expanded.map { |text, _splittable, brk, _quoted| (brk ? separator : '') + text }.join
      end

      # A case/removal pattern keeps quoting as backslash shielding so quoted
      # metacharacters remain literal when ShellPattern compiles the result.
      sig { params(pattern: AST::Word, tilde: Symbol).returns(String) }
      def expand_pattern(pattern, tilde: :leading)
        segments = tilde_expand(pattern.segments, tilde)
        segments.map { |segment| escape_if_quoted(segment, segment.expand(@executor)) }.join
      end

      private

      sig { params(word: AST::Word).returns(T::Array[FieldPart]) }
      def parts(word)
        expand_parts(word).map { |part| shield(part) }
      end

      sig { params(segments: T::Array[AST::WordSegment[T.untyped]], mode: Symbol).returns(T::Array[AST::WordSegment[T.untyped]]) }
      def tilde_expand(segments, mode)
        TILDE_EXPANDERS.fetch(mode).new(@executor, segments).expand
      end

      sig { params(fields: T::Array[String]).returns(T::Array[String]) }
      def glob(fields)
        fields.flat_map { |field| GlobExpander.new(@executor).expand(field) }
      end

      sig { params(segment: AST::WordSegment[T.untyped]).returns(T::Array[FieldPart]) }
      def field_parts(segment)
        return splat_parts(segment) if segment.splat?

        segment.field_parts(@executor)
      end

      # Glob metacharacters in quoted text are escaped so they match literally;
      # unquoted text keeps them active.
      sig { params(segment: AST::WordSegment[T.untyped], text: String).returns(String) }
      def escape_if_quoted(segment, text)
        segment.quoted ? escape(text) : text
      end

      sig { params(part: FieldPart).returns(FieldPart) }
      def shield(part)
        text, splittable, brk, quoted = part
        [quoted ? escape(text) : text, splittable, brk, quoted]
      end

      sig { params(text: String).returns(String) }
      def escape(text)
        text.gsub(/[\\*?\[\]\-!^]/) { |meta| "\\#{meta}" }
      end

      sig { params(segment: AST::WordSegment[T.untyped]).returns(T::Array[FieldPart]) }
      def splat_parts(segment)
        quoted = segment.quoted
        @executor.state.positional.map.with_index do |element, index|
          [element, !quoted, index.positive?, quoted]
        end
      end

      sig { returns(String) }
      def field_separator
        value = ifs
        value ? (value.each_char.first || '') : ' '
      end

      sig { returns(T.nilable(String)) }
      def ifs
        @executor.state.variables.get('IFS')
      end
    end
  end
end
