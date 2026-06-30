# typed: true
# frozen_string_literal: true

module Rush
  # The variable-environment side of the shell state, layered over one
  # Environment: dynamic `local` scoping (a stack of snapshots restored when a
  # function returns) and the logical working directory mirrored into
  # $PWD/$OLDPWD. Both are managed mutations of the same environment, so they
  # live together here, off ShellState.
  class Scope
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :pwd

    sig { params(environment: Environment).void }
    def initialize(environment)
      @environment = environment
      @frames = []
      @pwd = environment.get('PWD')
    end

    # Change the logical working directory, keeping $OLDPWD (the directory we
    # left) and $PWD (the one we entered) in step — the invariant cd relies on.
    sig { params(pwd: String).void }
    def move_to(pwd)
      @environment.assign('OLDPWD', @pwd)
      @pwd = pwd
      @environment.assign('PWD', pwd)
    end

    # Seed the logical pwd from the OS at startup when $PWD was unset; unlike
    # #move_to this records no $OLDPWD/$PWD — there is no directory we came from.
    sig { params(path: String).void }
    def seed_pwd(path)
      return if @pwd

      @pwd = path
    end

    # A function call brackets its body with begin/end_scope; declare_local
    # snapshots a variable so end_scope restores its prior value (or unsets it
    # when it had none).
    sig { void }
    def begin_scope
      @frames.push({})
    end

    sig { void }
    def end_scope
      # pop is non-nil here (paired with begin_scope); .to_a pins its type to an
      # array of pairs for the checker without changing behaviour on that path.
      @frames.pop.to_a.each { |name, value| restore(name, value) }
    end

    sig { returns(T::Boolean) }
    def in_function?
      @frames.any?
    end

    sig { params(name: String).void }
    def declare_local(name)
      # last frame is non-nil here (only called inside a function); fetch(-1) pins
      # its type to Hash for the checker and keeps the crash-if-empty invariant.
      frame = @frames.fetch(-1)
      frame[name] = @environment.get(name) unless frame.key?(name)
    end

    private

    sig { params(name: String, value: T.nilable(String)).void }
    def restore(name, value)
      value ? @environment.assign(name, value) : @environment.unset(name)
    end
  end
end
