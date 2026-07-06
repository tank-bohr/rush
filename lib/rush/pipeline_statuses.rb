# typed: true
# frozen_string_literal: true

module Rush
  # Chooses the observable status for a completed multi-stage pipeline.
  class PipelineStatuses
    extend T::Sig

    sig { params(entries: T::Array[Status]).void }
    def initialize(entries)
      @entries = entries
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
  end
end
