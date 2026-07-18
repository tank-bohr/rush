# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Orchestrates the ordered POSIX word expansion. Each segment expands itself
    # to one or more parts ([text, splittable, break_before, quoted]); unquoted results
    # undergo IFS field splitting and then pathname expansion. The one multi-field
    # case is "$@"/$@, which yields one part per positional parameter with a
    # forced field break between them ($* always joins to a scalar). Field
    # splitting carries quote provenance into the pathname-expansion boundary.
    class Pipeline
      extend T::Sig

      # Tilde expansion strategy per mode (its value is a word's segment list).
      TILDE_EXPANDERS = { none: NoTilde, leading: TildeExpander, assignment: AssignmentTilde }.freeze

      sig { params(executor: Executor).void }
      def initialize(executor)
        @executor = executor
        @glob_expander = GlobExpander.new(executor)
      end

      # Argv expansion: expand each word to fields (splitting unquoted on the IFS
      # value in force after that word's substitutions), then pathname-expand.
      sig { params(words: T::Array[AST::Word]).returns(T::Array[String]) }
      def expand(words)
        expanded = T.let([], T::Array[String])
        words.each { |word| append_word(word, expanded) }
        expanded
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
        expanded = T.let([], T::Array[FieldPart])
        tilde_expand(word.segments, tilde).each { |segment| append_field_parts(segment, expanded) }
        expanded
      end

      sig { params(expanded: T::Array[FieldPart]).returns(String) }
      def collapse(expanded)
        result = +''
        separator = field_separator
        expanded.each { |text, _splittable, brk, _quoted| result << (brk ? separator : '') << text }
        result
      end

      # A case/removal pattern keeps quoting as backslash shielding so quoted
      # metacharacters remain literal when ShellPattern compiles the result.
      sig { params(pattern: AST::Word, tilde: Symbol).returns(String) }
      def expand_pattern(pattern, tilde: :leading)
        result = +''
        tilde_expand(pattern.segments, tilde).each { |segment| result << expanded_pattern(segment) }
        result
      end

      private

      sig { params(segment: AST::AnySegment).returns(String) }
      def expanded_pattern(segment)
        escape_if_quoted(segment, segment.expand(@executor))
      end

      sig { params(word: AST::Word, expanded: T::Array[String]).void }
      def append_word(word, expanded)
        parts = expand_parts(word)
        FieldSplitter.new(ifs).split(parts).each { |field| @glob_expander.append(field, expanded) }
      end

      sig { params(segments: T::Array[AST::AnySegment], mode: Symbol).returns(T::Array[AST::AnySegment]) }
      def tilde_expand(segments, mode)
        TILDE_EXPANDERS.fetch(mode).new(@executor, segments).expand
      end

      sig { params(segment: AST::AnySegment, expanded: T::Array[FieldPart]).void }
      def append_field_parts(segment, expanded)
        return append_splat_parts(segment, expanded) if segment.splat?

        segment.append_field_parts(@executor, expanded)
      end

      # Glob metacharacters in quoted text are escaped so they match literally;
      # unquoted text keeps them active.
      sig { params(segment: AST::AnySegment, text: String).returns(String) }
      def escape_if_quoted(segment, text)
        segment.quoted ? escape(text) : text
      end

      sig { params(text: String).returns(String) }
      def escape(text)
        text.gsub(/[\\*?\[\]\-!^]/) { |meta| "\\#{meta}" }
      end

      sig { params(segment: AST::AnySegment, expanded: T::Array[FieldPart]).void }
      def append_splat_parts(segment, expanded)
        quoted = segment.quoted
        @executor.state.positional.to_a.each_with_index do |element, index|
          expanded << [element, !quoted, index.positive?, quoted]
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
