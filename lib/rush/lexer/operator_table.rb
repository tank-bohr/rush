# frozen_string_literal: true

module Rush
  class Lexer
    # Maximal-munch operator table: alternatives are tried longest-first so `>>`
    # beats `>`, `&&` beats `&`, `>|` beats `>`. Single-character operators are
    # their own token (matching the grammar's '<' '>' '|' '&' ';'); multi-char
    # operators map to named tokens. Dup operators (<& >&) join in a later slice.
    module OperatorTable
      OPERATORS = {
        '&&' => :AND_IF, '||' => :OR_IF, '>>' => :DGREAT,
        '<>' => :LESSGREAT, '>|' => :CLOBBER,
        '<' => '<', '>' => '>', '|' => '|', '&' => '&', ';' => ';'
      }.freeze

      PATTERN = Regexp.union(OPERATORS.keys.sort_by { |op| -op.length }).freeze
    end
  end
end
