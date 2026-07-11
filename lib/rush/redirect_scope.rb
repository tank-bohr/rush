# typed: true
# frozen_string_literal: true

module Rush
  # Applies command redirects on top of an IoTable and owns cleanup of streams
  # opened by those redirects. Redirect-only exec is detected by comparing the
  # yielded table with the executor's current base table after the block returns.
  class RedirectScope
    extend T::Sig

    sig { params(executor: T.untyped).void }
    def initialize(executor)
      @executor = executor
    end

    # Apply the redirects on top of a base IoTable (the executor's current one
    # by default), yield the result, then flush+close the files those redirects
    # opened (POSIX: a later command in the same shell sees the data). Only the
    # streams this command opened are closed — the diff against the base leaves
    # inherited streams and pipe ends untouched. Exception: redirect-only `exec`
    # commits the table as the shell's base (replace_io), so it now equals that
    # base — leave those files open so they persist for the rest of the shell
    # rather than closing them out from under it.
    sig do
      type_parameters(:U)
        .params(redirects: T::Array[AST::Redirect], base: IoTable,
                blk: T.proc.params(io: IoTable).returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_redirects(redirects, base = @executor.io, &blk)
      opened = T.let([], T::Array[FdEntry])
      io = apply_redirects(redirects, base, opened)
      yield io
    ensure
      close_redirect_io(T.must(opened), io || base)
    end

    private

    sig { params(redirects: T::Array[AST::Redirect], base: IoTable, opened: T::Array[FdEntry]).returns(IoTable) }
    def apply_redirects(redirects, base, opened)
      redirects.reduce(base) { |io, redirect| apply_redirect(redirect, io, opened) }
    end

    sig { params(redirect: AST::Redirect, io: IoTable, opened: T::Array[FdEntry]).returns(IoTable) }
    def apply_redirect(redirect, io, opened)
      redirected = redirect_into(redirect, io)
      opened.concat(redirected.opened_over(io))
      redirected
    end

    sig { params(opened: T::Array[FdEntry], io: IoTable).void }
    def close_redirect_io(opened, io)
      entries = io.equal?(@executor.io) ? opened - io.entries : opened
      IoTable.close_entries(entries, @executor.system)
    end

    sig { params(redirect: AST::Redirect, io: IoTable).returns(IoTable) }
    def redirect_into(redirect, io)
      target = @executor.expander.expand_value(redirect.target)
      @executor.redirections.fetch(redirect.kind).apply(redirect, target, io, @executor.system)
    end
  end
end
