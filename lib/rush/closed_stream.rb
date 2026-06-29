# frozen_string_literal: true

module Rush
  # A file descriptor closed by `n>&-` / `n<&-`. Any read or write raises a "bad
  # file descriptor" error so the command fails (status 1, as dash does);
  # IoTable#to_spawn_options maps it to :close so a spawned child gets the fd
  # closed too; close/flush are no-ops (it owns nothing).
  class ClosedStream
    %i[write print puts << printf gets read readline each_line readpartial].each do |method|
      # Kernel.raise (not bare raise): Steep can't resolve the receiver of a bare
      # raise inside a class-level define_method block (its self is untyped there).
      define_method(method) { |*_| Kernel.raise(Errno::EBADF) }
    end

    def close
      nil
    end

    def flush
      self
    end
  end
end
