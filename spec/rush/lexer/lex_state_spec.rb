# frozen_string_literal: true

RSpec.describe Rush::Lexer::LexState do
  subject(:state) { described_class.new }

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

  def advance(*tokens)
    tokens.each { |token| state.advance(token) }
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

  it 'keeps a paren-opened pattern separate from a subshell compound' do
    expect(symbols('case x in (x) for i in a b; do echo $i; done;; esac')).to eq(
      [:Case, :WORD, :In, '(', :WORD, ')', :For, :NAME, :In, :WORD, :WORD, ';', :Do,
       :WORD, :WORD, ';', :Done, :DSEMI, :Esac, false]
    )
  end

  it 'starts expecting a command in normal mode' do
    expect([state.expects_command?, state.command_mode?]).to eq([true, true])
  end

  it 'starts with every header predicate off' do
    predicates = [state.for_name?, state.for_in?, state.case_subject?,
                  state.case_in?, state.case_arm?, state.case_pat?]
    expect(predicates).to all(be(false))
  end

  it 'ends command position at the command word, staying in command mode' do
    advance(:WORD)
    expect([state.expects_command?, state.command_mode?]).to eq([false, true])
  end

  it 'returns to command position after a list introducer' do
    advance(:WORD, :NEWLINE)
    expect(state.expects_command?).to be(true)
  end

  it 'expects a filename, not a command, after a redirect operator' do
    advance('<')
    expect(state.expects_command?).to be(false)
  end

  it 'still expects the command once the redirect filename is consumed' do
    advance('<', :WORD)
    expect(state.expects_command?).to be(true)
  end

  it 'keeps command position across an IO number and an assignment word' do
    advance(:IO_NUMBER, :ASSIGNMENT_WORD)
    expect(state.expects_command?).to be(true)
  end

  it 'walks the for header: name, in, and commands resume at do' do
    advance(:For)
    expect([state.for_name?, state.command_mode?]).to eq([true, false])
    advance(:NAME)
    expect(state.for_in?).to be(true)
    advance(:Do)
    expect([state.for_in?, state.command_mode?]).to eq([false, true])
  end

  it 'walks the case header through subject, in, pattern and body' do
    advance(:Case)
    expect([state.case_subject?, state.command_mode?]).to eq([true, false])
    advance(:WORD)
    expect(state.case_in?).to be(true)
    advance(:In)
    expect(state.case_arm?).to be(true)
    advance(:WORD)
    expect(state.case_pat?).to be(true)
    advance(')')
    expect([state.command_mode?, state.case_pat?]).to eq([true, false])
  end

  it 'returns from a case body to the pattern arm at ;;' do
    advance(:Case, :WORD, :In, :WORD, ')', :WORD, :DSEMI)
    expect(state.case_arm?).to be(true)
  end

  it 'leaves case mode when esac closes an empty arm list' do
    advance(:Case, :WORD, :In, :Esac)
    expect([state.command_mode?, state.case_arm?]).to eq([true, false])
  end

  it 'restores the surrounding case body when a nested case closes' do
    advance(:Case, :WORD, :In, :WORD, ')')
    advance(:Case, :WORD, :In, :WORD, ')')
    advance(:WORD, :DSEMI, :Esac, :DSEMI)
    expect(state.case_arm?).to be(true)
  end

  it 'does not open a compound for the pattern paren of a later arm' do
    advance(:Case, :WORD, :In, :WORD, ')', :WORD, :DSEMI)
    advance('(', :WORD, ')')
    expect([state.command_mode?, state.case_arm?]).to eq([true, false])
  end

  it 'clears a pending filename at a list introducer' do
    advance('<', :NEWLINE)
    expect(state.expects_command?).to be(true)
  end
end
