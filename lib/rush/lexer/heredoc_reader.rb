# frozen_string_literal: true

module Rush
  class Lexer
    # Reads here-document bodies from the lexer's scanner once the command line's
    # terminating newline is reached. For each pending `<<word` holder it gathers
    # the following lines up to the delimiter line, strips leading tabs for the
    # `<<-` form, and parses the body for expansion unless the delimiter was
    # quoted (a quoted delimiter makes the body literal).
    class HeredocReader
      def initialize(scanner, interactive:)
        @scanner = scanner
        @interactive = interactive
      end

      # Fill each holder, in the order the `<<`s appeared, with its body.
      def fill(holders)
        holders.each { |holder| holder.fill(read(holder)) }
      end

      private

      def read(holder)
        build_body(holder, gather(holder, +''))
      end

      def gather(holder, out)
        line = heredoc_line(holder)
        return out unless line

        gather(holder, out << line)
      end

      def heredoc_line(holder)
        line = @scanner.scan(/[^\n]*\n?/)
        raise IncompleteInput, 'unterminated here-document' if line.to_s.empty? && @interactive
        return if line.to_s.empty? || delimiter?(holder, line)

        strip_tabs(holder, line)
      end

      def delimiter?(holder, line)
        strip_tabs(holder, line).chomp == holder.delimiter
      end

      def strip_tabs(holder, line)
        holder.strip ? line.sub(/\A\t+/, '') : line
      end

      # A quoted delimiter (<<'EOF') makes the body literal; an unquoted one is
      # parsed for expansion ($var, $(...), `...`), applied later at execution.
      def build_body(holder, text)
        return literal_word(text) if holder.quoted

        HeredocBody.new(text).scan
      end

      def literal_word(text)
        AST::Word.new([AST::LiteralSegment.new(text, false)])
      end
    end
  end
end
