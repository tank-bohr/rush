# frozen_string_literal: true

RSpec.describe Rush::Expansion::FieldSplitter do
  def fields(parts, ifs = nil)
    normalized = parts.map { |text, splittable, brk, quoted| [text, splittable, brk || false, quoted || false] }
    described_class.new(ifs).split(normalized)
  end

  def split(parts, ifs = nil)
    fields(parts, ifs).map(&:text)
  end

  describe 'default whitespace IFS' do
    it 'keeps a single literal part as one field' do
      expect(split([['abc', false]])).to eq(['abc'])
    end

    it 'splits an unquoted part on whitespace runs, dropping leading/trailing empties' do
      expect(split([['  a  b  ', true]])).to eq(%w[a b])
    end

    it 'does not split quoted or literal parts' do
      expect(split([['a b', false, false, true]])).to eq(['a b'])
    end

    it 'joins adjacent parts across a split boundary' do
      expect(split([['x', false], ['1 2', true], ['y', false]])).to eq(%w[x1 2y])
    end

    it 'starts a new field for a break-flagged part, keeping empties' do
      expect(split([['a', false], ['', false, true], ['b', false, true]])).to eq(['a', '', 'b'])
    end

    it 'keeps an empty quoted field but drops an empty unquoted expansion' do
      expect([split([['', false]]), split([['', true]])]).to eq([[''], []])
    end

    it 'drops empty unquoted splat elements when IFS contains whitespace' do
      parts = [['', true], ['x', true, true], ['', true, true], ['y', true, true]]
      expect(split(parts)).to eq(%w[x y])
      expect(split(parts, ' :')).to eq(%w[x y])
    end

    it 'keeps non-trailing empty splat elements when IFS has no whitespace' do
      parts = [['', true], ['x', true, true], ['', true, true], ['y', true, true], ['', true, true]]
      expect(split(parts, ':')).to eq(['', 'x', '', 'y'])
      expect(split(parts, ': ')).to eq(['', 'x', '', 'y'])
      expect(split(parts, '')).to eq(['', 'x', '', 'y'])
    end

    it 'keeps literal text separate from its quote-aware pathname pattern' do
      field = fields([['\\*', true], ['*', false, false, true]]).fetch(0)
      expect([field.text, field.pattern]).to eq(['\\**', '\\*\\*'])
    end
  end

  describe 'null IFS' do
    it 'performs no field splitting' do
      expect(split([['a b:c', true]], '')).to eq(['a b:c'])
    end

    it 'still separates break-flagged parts and drops empty unquoted expansions' do
      expect(split([['a', true], ['', true, true]], '')).to eq(['a'])
    end
  end

  describe 'custom non-whitespace IFS' do
    it 'splits on the delimiter, keeping a leading empty field' do
      expect(split([[':a:b', true]], ':')).to eq(['', 'a', 'b'])
    end

    it 'generates an empty field between adjacent delimiters' do
      expect(split([['a::b', true]], ':')).to eq(['a', '', 'b'])
    end

    it 'absorbs a single trailing delimiter without a trailing empty field' do
      expect(split([['a:b:', true]], ':')).to eq(%w[a b])
    end

    it 'keeps the empty field a doubled trailing delimiter produces' do
      expect(split([['a::', true]], ':')).to eq(['a', ''])
    end

    it 'splits a delimiter that spans two adjacent unquoted parts' do
      expect(split([['x:', true], [':y', true]], ':')).to eq(['x', '', 'y'])
    end
  end

  describe 'mixed whitespace and non-whitespace IFS' do
    it 'treats whitespace adjacent to a delimiter as part of that one delimiter' do
      expect(split([['a  :  b', true]], ' :')).to eq(%w[a b])
    end

    it 'strips leading and trailing whitespace but keeps the delimiter empties' do
      expect(split([[' :x: ', true]], ' :')).to eq(['', 'x'])
    end
  end
end
