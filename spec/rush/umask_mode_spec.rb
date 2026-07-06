# frozen_string_literal: true

RSpec.describe Rush::UmaskMode do
  it 'formats octal and symbolic masks' do
    expect([described_class.format_octal(0o022), described_class.format_symbolic(0o022)])
      .to eq(['0022', 'u=rwx,g=rx,o=rx'])
  end

  it 'parses octal masks using the low permission bits' do
    expect(described_class.parse('1777', 0o022)).to eq(0o777)
  end

  it 'parses symbolic masks as edits to allowed permissions' do
    expect(described_class.parse('u=rwx,g=rx,o=rx', 0o777)).to eq(0o022)
    expect(described_class.parse('g+w', 0o022)).to eq(0o002)
    expect(described_class.parse('g-w', 0o002)).to eq(0o022)
    expect(described_class.parse('a=rw', 0o022)).to eq(0o111)
  end

  it 'copies permissions between classes in symbolic masks' do
    expect(described_class.parse('g=u', 0o027)).to eq(0o007)
  end

  it 'rejects invalid symbolic masks' do
    expect(described_class.parse('u', 0o022)).to be_nil
    expect(described_class.parse('u=z', 0o022)).to be_nil
  end
end
