# frozen_string_literal: true

RSpec.describe Rush::Lexer::LexState do
  def symbols(source)
    lexer = Rush::Lexer.new(source)
    tokens = []
    loop do
      token = lexer.next_token.first
      tokens << token
      break if token == false
    end
    tokens
  end

  it 'tracks a for header nested directly inside a case body' do
    expect(symbols('case x in x) for i in a b; do echo $i; done;; esac')).to eq(
      [:Case, :WORD, :In, :WORD, ')', :For, :NAME, :In, :WORD, :WORD, ';', :Do,
       :WORD, :WORD, ';', :Done, :DSEMI, :Esac, false]
    )
  end

  it 'returns to the surrounding case body after a nested case' do
    expect(symbols('case x in x) case y in y) echo nested;; esac;; esac')).to eq(
      [:Case, :WORD, :In, :WORD, ')', :Case, :WORD, :In, :WORD, ')', :WORD, :WORD,
       :DSEMI, :Esac, :DSEMI, :Esac, false]
    )
  end
end
