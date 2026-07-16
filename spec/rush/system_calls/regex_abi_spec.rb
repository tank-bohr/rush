# frozen_string_literal: true

RSpec.describe Rush::SystemCalls::RegexAbi do
  it 'accepts only glibc 2 on 32/64-bit Linux ABIs' do
    cases = [
      ['linux', 8, '2.43'],
      ['linux-gnu', 4, '2.17'],
      ['darwin24', 8, '2.43'],
      ['linux-musl', 8, '2.43'],
      ['linux', 16, '2.43'],
      ['linux', 8, '3.0'],
      ['linux', 8, '2'],
      ['linux', 8, 'garbage']
    ]

    expect(cases.map { |host, pointer_size, version| described_class.supported?(host:, pointer_size:, version:) })
      .to eq([true, true, false, false, false, false, false, false])
  end

  it 'accepts the running host exactly when its independently read ABI facts are supported' do
    version = running_glibc_version
    expected = !version.nil? && described_class.supported?(
      host: RbConfig::CONFIG.fetch('host_os'), pointer_size: Fiddle::SIZEOF_VOIDP, version:
    )
    expect(described_class.available?).to be(expected)
  end

  it 'routes a future glibc major through the unsupported-ABI fallback' do
    handle = instance_double(Fiddle::Handle)
    allow(described_class).to receive(:libc_version).with(handle).and_return('3.0')
    expect(described_class.available?(handle)).to be(false)
  end

  it 'declines a C library without the glibc version symbol' do
    handle = instance_double(Fiddle::Handle)
    allow(handle).to receive(:[]).with('gnu_get_libc_version').and_raise(Fiddle::DLError)
    expect(described_class.available?(handle)).to be(false)
  end

  it 'declines a pathological null glibc version pointer without dereferencing it' do
    handle = instance_double(Fiddle::Handle)
    pointer = instance_spy(Fiddle::Pointer, null?: true)
    function = instance_double(Fiddle::Function, call: pointer)
    allow(handle).to receive(:[]).with('gnu_get_libc_version').and_return(7)
    allow(Fiddle::Function).to receive(:new).with(7, [], Fiddle::TYPE_VOIDP).and_return(function)
    allow(pointer).to receive(:to_s).and_return('unexpected')
    expect(described_class.available?(handle)).to be(false)
    expect(pointer).not_to have_received(:to_s)
  end

  def running_glibc_version
    handle = Fiddle::Handle::DEFAULT
    function = Fiddle::Function.new(handle['gnu_get_libc_version'], [], Fiddle::TYPE_VOIDP)
    pointer = function.call
    pointer.to_s unless pointer.null?
  rescue Fiddle::DLError
    nil
  end
end
