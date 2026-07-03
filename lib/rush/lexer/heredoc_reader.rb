# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Reads here-document bodies from the lexer's scanner once the command line's
    # terminating newline is reached. For each pending `<<word` holder it gathers
    # the following lines up to the delimiter line, strips leading tabs for the
    # `<<-` form, and parses the body for expansion unless the delimiter was
    # quoted (a quoted delimiter makes the body literal).
    class HeredocReader
      extend T::Sig

      sig { params(scanner: StringScanner, interactive: T::Boolean).void }
      def initialize(scanner, interactive:)
        @scanner = scanner
        @interactive = interactive
      end

      # Fill each holder, in the order the `<<`s appeared, with its body.
      sig { params(holders: T::Array[HereDoc]).void }
      def fill(holders)
        holders.each { |holder| holder.fill(read(holder)) }
      end

      private

      sig { params(holder: HereDoc).returns(AST::Word) }
      def read(holder)
        build_body(holder, gather(holder, +''))
      end

      sig { params(holder: HereDoc, out: String).returns(String) }
      def gather(holder, out)
        line = heredoc_line(holder)
        return out unless line

        gather(holder, out << line)
      end

      sig { params(holder: HereDoc).returns(T.nilable(String)) }
      def heredoc_line(holder)
        return eof_line if @scanner.eos?

        line = read_line
        return if delimiter?(holder, line)

        strip_tabs(holder, line)
      end

      sig { returns(T.nilable(String)) }
      def eof_line
        raise IncompleteInput, 'unterminated here-document' if @interactive
      end

      sig { returns(String) }
      def read_line
        @scanner.scan_until(/\n/) || rest_line
      end

      sig { returns(String) }
      def rest_line
        @scanner.rest.tap { @scanner.terminate }
      end

      sig { params(holder: HereDoc, line: String).returns(T::Boolean) }
      def delimiter?(holder, line)
        strip_tabs(holder, line).chomp == holder.delimiter
      end

      sig { params(holder: HereDoc, line: String).returns(String) }
      def strip_tabs(holder, line)
        holder.strip ? line.sub(/\A\t+/, '') : line
      end

      # A quoted delimiter (<<'EOF') makes the body literal; an unquoted one is
      # parsed for expansion ($var, $(...), `...`), applied later at execution.
      sig { params(holder: HereDoc, text: String).returns(AST::Word) }
      def build_body(holder, text)
        return literal_word(text) if holder.quoted

        HeredocBody.new(text).scan
      end

      sig { params(text: String).returns(AST::Word) }
      def literal_word(text)
        AST::Word.new([AST::LiteralSegment.new(text, false)])
      end
    end
  end
end
