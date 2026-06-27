# frozen_string_literal: true

RSpec.describe Rush::Lexer do
  def symbols(source)
    lexer = described_class.new(source)
    result = []
    loop do
      token = lexer.next_token
      break if token == [false, false]

      result << token.first
    end
    result
  end

  it 'emits a WORD token carrying a literal word' do
    symbol, word = described_class.new('echo').next_token
    expect(symbol).to eq(:WORD)
    expect(word.literal_text).to eq('echo')
  end

  it 'separates words, semicolons and newlines while skipping blanks' do
    expect(symbols("a b;c\nd")).to eq([:WORD, :WORD, ';', :WORD, :NEWLINE, :WORD])
  end

  it 'skips a comment to the end of the line' do
    expect(symbols('echo hi # trailing comment')).to eq(%i[WORD WORD])
  end

  it 'tokenizes operators with maximal munch' do
    expect(symbols('a&&b||c|d')).to eq([:WORD, :AND_IF, :WORD, :OR_IF, :WORD, '|', :WORD])
  end

  it 'emits redirection operators and an IO_NUMBER before them' do
    expect(symbols('cat 2>f >>g')).to eq([:WORD, :IO_NUMBER, '>', :WORD, :DGREAT, :WORD])
  end

  it 'recognizes an assignment word in command-prefix position' do
    symbol, value = described_class.new('X=1').next_token
    expect(symbol).to eq(:ASSIGNMENT_WORD)
    expect([value.name, value.value.literal_text]).to eq(%w[X 1])
  end

  it 'treats name=value after the command word as a plain WORD' do
    expect(symbols('echo X=1')).to eq(%i[WORD WORD])
  end

  it 'keeps quoted segments in an assignment value' do
    symbol, value = described_class.new('x="a b"').next_token
    expect(symbol).to eq(:ASSIGNMENT_WORD)
    expect(value.value.literal_text).to eq('a b')
  end

  it 'does not treat a quoted name as an assignment' do
    expect(symbols('"x"=1')).to eq([:WORD])
  end

  it 'recognizes reserved words only in command position' do
    expect(symbols('if x; then y; fi')).to eq([:If, :WORD, ';', :Then, :WORD, ';', :Fi])
  end

  it 'treats a reserved word as a plain WORD in argument position' do
    expect(symbols('echo if then')).to eq(%i[WORD WORD WORD])
  end

  it 'does not treat a quoted reserved word as reserved' do
    expect(symbols("'if'")).to eq([:WORD])
  end

  it 'does not treat a redirection target as a reserved word' do
    expect(symbols('echo > if')).to eq([:WORD, '>', :WORD])
  end

  it 'recognizes brace-group tokens and the bang' do
    expect(symbols('! { echo; }')).to eq([:Bang, :Lbrace, :WORD, ';', :Rbrace])
  end

  it 'recognizes the loop reserved words' do
    expect(symbols('while x; do y; done')).to eq([:While, :WORD, ';', :Do, :WORD, ';', :Done])
  end

  it 'recognizes the for header: NAME then in then the word list' do
    expect(symbols('for i in a; do x; done'))
      .to eq([:For, :NAME, :In, :WORD, ';', :Do, :WORD, ';', :Done])
  end

  it 'recognizes a for header with no in clause' do
    expect(symbols('for i; do x; done')).to eq([:For, :NAME, ';', :Do, :WORD, ';', :Done])
  end

  it 'falls back to WORD for a non-in/do word in the for header' do
    expect(symbols('for i x')).to eq(%i[For NAME WORD])
  end

  it 'does not treat a quoted word as the for in/do keyword' do
    expect(symbols("for i 'in'")).to eq(%i[For NAME WORD])
  end

  it 'recognizes the case header, alternation patterns and arm terminators' do
    expect(symbols('case x in a|b) echo;; esac'))
      .to eq([:Case, :WORD, :In, :WORD, '|', :WORD, ')', :WORD, :DSEMI, :Esac])
  end

  it 'treats a reserved word as a literal case pattern' do
    expect(symbols('case x in if) echo;; esac'))
      .to eq([:Case, :WORD, :In, :WORD, ')', :WORD, :DSEMI, :Esac])
  end

  describe 'here-documents' do
    def tokens(source)
      lexer = described_class.new(source)
      out = []
      loop { (token = lexer.next_token) == [false, false] ? break : out << token }
      out
    end

    it 'tokenizes << and the delimiter, collecting the body at the newline' do
      toks = tokens("cat <<EOF\nhello\nworld\nEOF\n")
      holder = toks[2].last
      expect(toks.map(&:first)).to eq(%i[WORD DLESS WORD NEWLINE])
      expect([holder.delimiter, holder.quoted, holder.strip]).to eq(['EOF', false, false])
      expect(holder.body.literal_text).to eq("hello\nworld\n")
    end

    it 'marks a quoted delimiter and strips leading tabs for <<-' do
      holder = tokens("cat <<-'EOF'\n\t\tbody\n\tEOF\n")[2].last
      expect([holder.delimiter, holder.quoted, holder.strip]).to eq(['EOF', true, true])
      expect(holder.body.literal_text).to eq("body\n")
    end

    it 'collects multiple here-documents in order' do
      toks = tokens("cat <<A <<B\nfirst\nA\nsecond\nB\n")
      expect([toks[2].last.body.literal_text, toks[4].last.body.literal_text]).to eq(%W[first\n second\n])
    end

    it 'reads an unterminated here-document to the end of input' do
      expect(tokens("cat <<EOF\nonly\n")[2].last.body.literal_text).to eq("only\n")
    end
  end

  it 'signals end of input with [false, false]' do
    expect(described_class.new('').next_token).to eq([false, false])
  end

  it 'reports the scanner position as its location' do
    lexer = described_class.new('ab cd')
    lexer.next_token
    expect(lexer.location).to be >= 2
  end
end
