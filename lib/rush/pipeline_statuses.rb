# typed: true
# frozen_string_literal: true

module Rush
  # Chooses the observable status for a settled multi-stage pipeline: the
  # last stage's (or, under pipefail, the rightmost failure), with any
  # stage's stop signal riding along — a ^Z parks the whole job even when
  # the final stage had already exited (Status#with_stop, dash-probed).
  class PipelineStatuses
    extend T::Sig

    sig { params(entries: T::Array[Status]).void }
    def initialize(entries)
      @entries = entries
    end

    sig { returns(Status) }
    def verdict
      last_stage.with_stop(job_stopsig)
    end

    sig { returns(Status) }
    def pipefail_verdict
      pipefail.with_stop(job_stopsig)
    end

    sig { returns(Status) }
    def last_stage
      @entries.fetch(-1)
    end

    sig { returns(Status) }
    def pipefail
      @entries.reverse_each { |status| return status unless status.success? }
      Status.success
    end

    private

    sig { returns(T.nilable(Integer)) }
    def job_stopsig
      @entries.filter_map(&:stopsig).first
    end
  end
end
