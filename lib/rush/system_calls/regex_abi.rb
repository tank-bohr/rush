# typed: true
# frozen_string_literal: true

require 'fiddle'
require 'rbconfig'

module Rush
  class SystemCalls
    # Runtime half of the glibc regex_t safety contract. POSIX leaves regex_t
    # opaque, so rush enables its Fiddle bridge only for the glibc-2 Linux ABI
    # whose word-scaled public layout fits this buffer on 32/64-bit hosts. The
    # Docker C probe verifies the exact sizeof/alignment on the release image.
    module RegexAbi
      extend T::Sig

      REGEX_BYTES = 256
      POINTER_BYTES = [4, 8].freeze
      LINUX = /\Alinux(?:-gnu)?\z/
      GLIBC_2 = /\A2\.\d+\z/

      sig { params(handle: T.untyped).returns(T::Boolean) }
      def self.available?(handle = Fiddle::Handle::DEFAULT)
        version = libc_version(handle)
        host = RbConfig::CONFIG.fetch('host_os')
        version ? supported?(host:, pointer_size: Fiddle::SIZEOF_VOIDP, version:) : false
      rescue Fiddle::DLError
        false
      end

      sig { params(host: String, pointer_size: Integer, version: String).returns(T::Boolean) }
      def self.supported?(host:, pointer_size:, version:)
        host.match?(LINUX) && POINTER_BYTES.include?(pointer_size) && version.match?(GLIBC_2)
      end

      sig { params(handle: T.untyped).returns(T.nilable(String)) }
      def self.libc_version(handle)
        function = Fiddle::Function.new(handle['gnu_get_libc_version'], [], Fiddle::TYPE_VOIDP)
        pointer = function.call
        pointer.to_s unless pointer.null?
      end
      private_class_method :libc_version
    end
  end
end
