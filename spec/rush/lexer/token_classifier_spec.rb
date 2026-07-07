# frozen_string_literal: true

RSpec.describe Rush::Lexer::TokenClassifier do
  def state_after(*tokens)
    state = Rush::Lexer::LexState.new
    tokens.each { |token| state.advance(token) }
    state
  end

  def classify(word, state)
    described_class.new(word, state).call
  end

  it 'classifies a reserved word in command position, carrying the word' do
    word = Rush::AST::Word.literal('if')
    expect(classify(word, state_after)).to eq([:If, word])
  end

  it 'leaves a reserved word after the command name a plain WORD' do
    word = Rush::AST::Word.literal('if')
    expect(classify(word, state_after(:WORD))).to eq([:WORD, word])
  end

  it 'never reserves a quoted word' do
    word = Rush::AST::Word.new([Rush::AST::LiteralSegment.new('if', true)])
    expect(classify(word, state_after)).to eq([:WORD, word])
  end

  it 'recognizes an assignment word, keeping name, value and source line' do
    word = Rush::AST::Word.literal('X=1', source_line: 7)
    symbol, assignment = classify(word, state_after)
    expect([symbol, assignment.name, assignment.value.literal_text, assignment.value.source_line])
      .to eq([:ASSIGNMENT_WORD, 'X', '1', 7])
  end

  it 'keeps quoted tail segments in the assignment value' do
    segments = [Rush::AST::LiteralSegment.new('X=a', false), Rush::AST::LiteralSegment.new('b c', true)]
    _symbol, assignment = classify(Rush::AST::Word.new(segments), state_after)
    expect(assignment.value.literal_text).to eq('ab c')
  end

  it 'keeps the assignment remainder unquoted' do
    _symbol, assignment = classify(Rush::AST::Word.literal('X=1'), state_after)
    expect(assignment.value.segments.first.literal_value).to eq('1')
  end

  it 'treats name=value after the command name as a plain WORD' do
    word = Rush::AST::Word.literal('X=1')
    expect(classify(word, state_after(:WORD))).to eq([:WORD, word])
  end

  it 'rejects an assignment whose name is not a NAME' do
    word = Rush::AST::Word.literal('2X=1')
    expect(classify(word, state_after)).to eq([:WORD, word])
  end

  it 'rejects an assignment whose head segment is quoted' do
    word = Rush::AST::Word.new([Rush::AST::LiteralSegment.new('X=', true)])
    expect(classify(word, state_after)).to eq([:WORD, word])
  end

  it 'forces any word to NAME in the for-name position' do
    word = Rush::AST::Word.literal('if')
    expect(classify(word, state_after(:For))).to eq([:NAME, word])
  end

  it 'recognizes in and do closing a for header' do
    state = state_after(:For, :NAME)
    in_word = Rush::AST::Word.literal('in')
    expect(classify(in_word, state)).to eq([:In, in_word])
    expect(classify(Rush::AST::Word.literal('do'), state).first).to eq(:Do)
  end

  it 'falls back to WORD for a non-keyword in the for header' do
    word = Rush::AST::Word.literal('x')
    expect(classify(word, state_after(:For, :NAME))).to eq([:WORD, word])
  end

  it 'leaves in and do plain words outside their headers' do
    in_word = Rush::AST::Word.literal('in')
    do_word = Rush::AST::Word.literal('do')
    expect(classify(in_word, state_after(:WORD))).to eq([:WORD, in_word])
    expect(classify(do_word, state_after(:WORD))).to eq([:WORD, do_word])
  end

  it 'falls back to WORD for a non-in word after the case subject' do
    word = Rush::AST::Word.literal('x')
    expect(classify(word, state_after(:Case, :WORD))).to eq([:WORD, word])
  end

  it 'recognizes in after the case subject' do
    word = Rush::AST::Word.literal('in')
    expect(classify(word, state_after(:Case, :WORD))).to eq([:In, word])
  end

  it 'needs a bare literal in for in after the case subject' do
    segments = [Rush::AST::LiteralSegment.new('i', false), Rush::AST::LiteralSegment.new('n', true)]
    word = Rush::AST::Word.new(segments)
    expect(classify(word, state_after(:Case, :WORD))).to eq([:WORD, word])
  end

  it 'forces the case subject to a plain WORD' do
    word = Rush::AST::Word.literal('if')
    expect(classify(word, state_after(:Case))).to eq([:WORD, word])
  end

  it 'forces a case pattern to a plain WORD even in command position' do
    word = Rush::AST::Word.literal('if')
    expect(classify(word, state_after(:Case, :WORD, :In, :WORD, '|'))).to eq([:WORD, word])
  end

  it 'reserves only esac inside a pattern arm' do
    state = state_after(:Case, :WORD, :In)
    if_word = Rush::AST::Word.literal('if')
    expect(classify(Rush::AST::Word.literal('esac'), state).first).to eq(:Esac)
    expect(classify(if_word, state)).to eq([:WORD, if_word])
  end
end
