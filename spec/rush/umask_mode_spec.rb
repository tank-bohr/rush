# frozen_string_literal: true

RSpec.describe Rush::UmaskMode do
  it 'formats octal and symbolic masks' do
    expect([described_class.format_octal(0o022), described_class.format_symbolic(0o022)])
      .to eq(['0022', 'u=rwx,g=rx,o=rx'])
  end

  it 'parses octal masks using the low permission bits' do
    expect(described_class.parse('1777', 0o022)).to eq(0o777)
    expect(described_class.parse('22', 0o777)).to eq(0o022)
  end

  it 'clamps formatting to the permission bits, mirroring the octal parse' do
    expect(described_class.format_octal(0o1777)).to eq('0777')
  end

  it 'parses symbolic masks as edits to allowed permissions' do
    expect(described_class.parse('u=rwx,g=rx,o=rx', 0o777)).to eq(0o022)
    expect(described_class.parse('g+w', 0o022)).to eq(0o002)
    expect(described_class.parse('g-w', 0o002)).to eq(0o022)
    expect(described_class.parse('a=rw', 0o022)).to eq(0o111)
  end

  it 'defaults an omitted who to all classes (dash-verified)' do
    expect(described_class.parse('+w', 0o022)).to eq(0o000)
    expect(described_class.parse('=r', 0o022)).to eq(0o333)
  end

  it 'assigns strictly within the named class, leaving the others intact' do
    # `=` clears exactly the who classes (all 3 permission bits) before
    # setting: g/o keep their sole x bit, u drops to r (dash-verified).
    expect(described_class.parse('u=r', 0o066)).to eq(0o366)
  end

  it 'absorbs duplicate who letters and permissions (dash-verified)' do
    # Even-count duplicates would cancel under a xor accumulator: the ua
    # pair pins each reduce as a true bitwise-or (mutant-derived).
    expect(described_class.parse('uua+w', 0o277)).to eq(0o055)
    expect(described_class.parse('ua+w', 0o277)).to eq(0o055)
    expect(described_class.parse('ua=w', 0o277)).to eq(0o555)
    expect(described_class.parse('ua=g', 0o427)).to eq(0o222)
    expect(described_class.parse('u+rr', 0o777)).to eq(0o377)
  end

  it 'copies only the source class window, into every named class (dash-verified)' do
    # g=o with u/g bits set: an unmasked source would drag the source's
    # neighbours into the target classes.
    expect(described_class.parse('g=o', 0o427)).to eq(0o477)
    expect(described_class.parse('a=u', 0o027)).to eq(0o000)
  end

  it 'copies permissions between classes in symbolic masks' do
    expect(described_class.parse('g=u', 0o027)).to eq(0o007)
  end

  it 'rejects invalid symbolic masks' do
    expect(described_class.parse('u', 0o022)).to be_nil
    expect(described_class.parse('u=z', 0o022)).to be_nil
    expect(described_class.parse('u~w', 0o022)).to be_nil
    # POSIX symbolic-mode grammar admits no trailing comma and bash agrees;
    # dash alone accepts exactly one (parser artifact) — the standard wins.
    expect(described_class.parse('u+w,', 0o022)).to be_nil
  end
end
