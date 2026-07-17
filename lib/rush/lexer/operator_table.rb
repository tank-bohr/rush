# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Maximal-munch operator table: alternatives are tried longest-first so `>>`
    # beats `>`, `&&` beats `&`, `>|` beats `>`, and the fd-dup `>&`/`<&` beat
    # `>`/`<` then `&`. Single-character operators are their own token (matching
    # the grammar's '<' '>' '|' '&' ';'); multi-char operators map to named tokens.
    module OperatorTable
      OPERATORS = T.let({
        '<<-' => :DLESSDASH, '&&' => :AND_IF, '||' => :OR_IF, '>>' => :DGREAT,
        '<<' => :DLESS, ';;' => :DSEMI, '<>' => :LESSGREAT, '>|' => :CLOBBER,
        '>&' => :GREATAND, '<&' => :LESSAND,
        '<' => '<', '>' => '>', '|' => '|', '&' => '&', ';' => ';', '(' => '(', ')' => ')'
      }.freeze, T::Hash[String, T.any(Symbol, String)])

      # POSIX 2.2.1 removes a backslash-newline before tokenization — even between
      # the characters of one operator: dash splices it at the character read
      # (pgetc_eatbnl), so `&\<newline>&` lexes as `&&`. Each alternative therefore
      # admits continuation pairs between its characters; the lexer splices them
      # back out of the match before looking the operator up.
      CONTINUATION = T.let(/\\\n/, Regexp)

      splice = "(?:#{CONTINUATION.source})*"
      longest_first = OPERATORS.keys.sort_by { |op| -op.length }
      PATTERN = T.let(Regexp.new(
        longest_first.map { |op| op.chars.map { |char| Regexp.escape(char) }.join(splice) }.join('|')
      ).freeze, Regexp)
    end
  end
end
