# frozen_string_literal: true

RSpec.describe Rush::Lexer::CaseFrame do
  subject(:frame) { described_class.new(2) }

  it 'walks case -> subject -> in -> pattern, holding await_in for other words' do
    expect(frame.state).to eq(:case_word)
    frame.word('subject')
    expect(frame.state).to eq(:await_in)
    frame.word('not-in')
    expect(frame.state).to eq(:await_in)
    frame.word('in')
    expect(frame.state).to eq(:pattern)
  end

  it 'answers pattern? only in pattern state at its own paren depth' do
    enter_pattern
    expect([frame.pattern?(2), frame.pattern?(3)]).to eq([true, false])
  end

  it 'pops on esac in pattern position without marking the pattern' do
    enter_pattern
    expect(frame.word('esac')).to eq(:pop)
    expect(frame.marked_pattern?(2)).to be(false)
  end

  it 'marks the pattern once a pattern word lands, at its depth only' do
    enter_pattern
    expect(frame.marked_pattern?(2)).to be(false)
    expect(frame.word('x')).to eq(:none)
    expect([frame.marked_pattern?(2), frame.marked_pattern?(3)]).to eq([true, false])
  end

  it 'opens the optional ( group form only before any pattern word' do
    enter_pattern
    frame.group(2)
    expect([frame.grouped?(2), frame.grouped?(3)]).to eq([true, false])
  end

  it 'ignores ( after a pattern word was seen' do
    enter_pattern
    frame.word('x')
    frame.group(2)
    expect(frame.grouped?(2)).to be(false)
  end

  it 'ignores ( arriving at a different depth' do
    enter_pattern
    frame.group(5)
    expect(frame.grouped?(2)).to be(false)
  end

  it 'reopens pattern position on ;; only from the body at depth, clearing marks' do
    enter_pattern
    frame.word('x')
    frame.body
    frame.reopen(3)
    expect(frame.pattern?(2)).to be(false)
    frame.reopen(2)
    expect([frame.pattern?(2), frame.marked_pattern?(2), frame.grouped?(2)]).to eq([true, false, false])
  end

  def enter_pattern
    frame.word('subject')
    frame.word('in')
  end
end
