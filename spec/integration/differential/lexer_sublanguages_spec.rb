# frozen_string_literal: true

RSpec.describe 'rush vs dash (lexer sublanguage matrix)' do
  before { skip 'dash not installed' unless system('command -v dash > /dev/null 2>&1') }

  contexts = {
    'nested braced parameter operators' =>
      'unset a b c; printf \'<%s>\\n\' "${a:-${b:-${c:-fallback}}}"',
    'a command substitution ending in a brace inside a braced operator word' =>
      'unset x; printf \'<%s>\\n\' "${x:-$(printf \'%s\' \'}\')}"',
    'a single quote treated literally inside a quoted braced parameter' =>
      'unset x; printf \'<%s>\\n\' "${x:-\'}"',
    'quoted close-parens and a nested command substitution' =>
      'printf \'<%s>\\n\' "$(printf \'%s\' \')\'; printf \'%s\' "$(printf x)")"',
    'a close-paren inside a command-substitution comment' =>
      "printf '<%s>\\n' \"$(printf x # ) ignored\n)\"",
    'parentheses and command substitution inside arithmetic expansion' =>
      'n=2; printf \'<%s>\\n\' "$(( (1 + n) * $(printf 3) ))"',
    'arithmetic expansion inside a braced operator word' =>
      'unset x; n=4; printf \'<%s>\\n\' "${x:-$((n + (2 * 3)))}"',
    'nested case constructs inside command substitution' =>
      'printf \'<%s>\\n\' "$(case x in (x) case y in y) printf yes;; esac;; esac)"',
    'a quoted close-paren in a case pattern inside command substitution' =>
      'printf \'<%s>\\n\' "$(case \')\' in \')\') printf quoted;; esac)"',
    'command substitution in a case pattern inside command substitution' =>
      'v=x; printf \'<%s>\\n\' "$(case "$v" in $(printf x)) printf dynamic;; esac)"',
    'all substitution forms in an unquoted here-document' => <<~SH,
      unset x; cat <<EOF
      ${x:-$(printf no)}:$((1 + 2)):$(printf C)
      EOF
    SH
    'a quoted here-document suppressing all substitution forms' => <<~SH,
      x=V; cat <<'EOF'
      ${x}:$(printf C):$((1 + 2))
      EOF
    SH
    'braced quote rules while expanding an unquoted here-document' => <<~SH,
      unset x; cat <<EOF
      ${x:-'}
      EOF
    SH
    'a here-document and nested substitutions inside a case body' => <<~SH
      v=x; case "$v" in x) cat <<EOF
      $(printf body):${v:-no}:$((2 + 3))
      EOF
      ;; esac
    SH
  }.freeze

  contexts.each.with_index(1) do |(context, snippet), index|
    id = format('lexer-context-%03d', index)

    it "#{id}: matches dash for #{context}" do
      expect(rush(snippet)).to eq(dash(snippet))
    end
  end
end
