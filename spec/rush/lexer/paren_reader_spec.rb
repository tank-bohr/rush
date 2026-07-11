# frozen_string_literal: true

RSpec.describe Rush::Lexer::ParenReader do
  def read(source)
    scanner = StringScanner.new(source)
    [described_class.new(scanner).read, scanner.rest]
  end

  it 'reads a balanced parenthesised body and consumes the closing paren' do
    expect(read('echo (nested) done) rest')).to eq(['echo (nested) done', ' rest'])
  end

  it 'does not count parens inside double quotes' do
    expect(read('echo ")") rest')).to eq(['echo ")"', ' rest'])
  end

  it 'does not count parens inside single quotes' do
    expect(read("echo ')(') rest")).to eq(["echo ')('", ' rest'])
  end

  it 'does not count a backslash-escaped paren' do
    expect(read('echo \)) rest')).to eq(['echo \)', ' rest'])
  end

  it 'keeps a backslash pair inside double quotes' do
    expect(read('echo "\")") rest')).to eq(['echo "\")"', ' rest'])
  end

  it 'skips a nested $( ... ) inside double quotes whole' do
    expect(read('echo "$(echo ")")") rest')).to eq(['echo "$(echo ")")"', ' rest'])
  end

  it 'skips a ${ ... } reference containing a paren' do
    expect(read('echo ${a:-)}) rest')).to eq(['echo ${a:-)}', ' rest'])
  end

  it 'skips a backtick region containing a paren' do
    expect(read('echo `echo ")"`) rest')).to eq(['echo `echo ")"`', ' rest'])
  end

  it 'does not count a paren inside a word-start # comment' do
    expect(read("echo hi #c )\n) rest")).to eq(["echo hi #c )\n", ' rest'])
  end

  it 'treats a mid-word # as an ordinary character' do
    expect(read('echo a#) rest')).to eq(['echo a#', ' rest'])
  end

  it 'starts a comment after a redirection operator, as dash does' do
    expect { read('echo x>#)') }.to raise_error(Rush::IncompleteInput, /unterminated \$\(/)
  end

  it 'swallows the unbalanced ) of a case pattern' do
    expect(read('case x in x) echo y;; esac) rest')).to eq(['case x in x) echo y;; esac', ' rest'])
  end

  it 'keeps case tracking across a newline before the first pattern and after ;;' do
    body = "case x in\nx) echo one;;\ny) echo two;; esac"
    expect(read("#{body}) rest")).to eq([body, ' rest'])
  end

  # dash rejects a newline between a pattern word and its `)` at parse time;
  # the abandoned frame lets that `)` close the substitution, so the invalid
  # construct fails at the re-parse (exit 2), as it does in dash.
  it 'abandons a case pattern interrupted by a newline' do
    expect(read("case x in x\n) echo y;; esac)")).to eq(["case x in x\n", ' echo y;; esac)'])
  end

  it 'tracks nested case constructs' do
    body = 'case x in x) case y in y) echo z;; esac;; esac'
    expect(read("#{body}) rest")).to eq([body, ' rest'])
  end

  it 'closes a grouped (pattern) back into the item body' do
    body = 'case x in (x) case y in y) echo z;; esac;; esac'
    expect(read("#{body}) rest")).to eq([body, ' rest'])
  end

  it 'keeps a case pattern that is itself a command substitution' do
    body = 'case $(echo x) in x) echo dyn;; esac'
    expect(read("#{body}) rest")).to eq([body, ' rest'])
  end

  it 'reads a quoted region as the case subject' do
    body = 'case "$x" in "") echo empty;; esac'
    expect(read("#{body}) rest")).to eq([body, ' rest'])
  end

  it 'keeps a case word that is not at a command position ordinary' do
    expect(read('echo case) rest')).to eq(['echo case', ' rest'])
  end

  it 'keeps an esac word with no open construct ordinary' do
    expect(read('esac) rest')).to eq(['esac', ' rest'])
  end

  it 'recognises case after a continuing reserved word' do
    body = 'if true; then case x in x) echo y;; esac; fi'
    expect(read("#{body}) rest")).to eq([body, ' rest'])
  end

  it 'skips a ${ ... } inside double quotes' do
    expect(read('echo "${a:-)}") rest')).to eq(['echo "${a:-)}"', ' rest'])
  end

  it 'skips a backtick region inside double quotes' do
    expect(read('echo "`echo hi`") rest')).to eq(['echo "`echo hi`"', ' rest'])
  end

  it 'ignores a ;; outside any case construct' do
    expect(read('echo a;;echo b) rest')).to eq(['echo a;;echo b', ' rest'])
  end

  it 'leaves pattern position alone on a stray ;;' do
    body = 'case x in ;; x) echo y;; esac'
    expect(read("#{body}) rest")).to eq([body, ' rest'])
  end

  it 'does not pop a case construct on an esac inside a nested subshell' do
    body = 'case x in x) (esac);; esac'
    expect(read("#{body}) rest")).to eq([body, ' rest'])
  end

  it 'raises IncompleteInput at end of input' do
    expect { read('echo no close') }.to raise_error(Rush::IncompleteInput, /unterminated \$\(/)
  end

  it 'raises IncompleteInput on an unterminated double quote' do
    expect { read('echo "a') }.to raise_error(Rush::IncompleteInput, /unterminated double/)
  end

  it 'raises IncompleteInput on an unterminated single quote' do
    expect { read("echo 'a") }.to raise_error(Rush::IncompleteInput, /unterminated single/)
  end

  # Named residue (rush-no1.9): dash re-parses the $( ... ) body, so a `)`
  # inside a here-document body does not close the substitution; the reader
  # is quote/comment/case-aware but not heredoc-aware and closes at the
  # first bare `)`. `echo $(cat <<E ... )` therefore still diverges.
  it 'pins the heredoc residue: a heredoc body paren closes the substitution' do
    expect(read("cat <<E\n)\nE\n)")).to eq(["cat <<E\n", "\nE\n)"])
  end
end
