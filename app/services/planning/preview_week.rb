module Planning
  PreviewWeek = Data.define(
    :starts_on,
    :ends_on,
    :phase,
    :recovery_week,
    :partial,
    :prescriptions,
    :duration_minutes,
    :estimated_tss,
    :estimated_work_kj,
    :warning) do
    def initialize(starts_on:, ends_on:, phase:, recovery_week:, partial:, prescriptions:, duration_minutes:, estimated_tss:, estimated_work_kj:, warning: nil)
      super(
        starts_on: starts_on,
        ends_on: ends_on,
        phase: phase.to_s.dup.freeze,
        recovery_week: recovery_week,
        partial: partial,
        prescriptions: prescriptions.freeze,
        duration_minutes: duration_minutes,
        estimated_tss: estimated_tss,
        estimated_work_kj: estimated_work_kj,
        warning: warning&.dup&.freeze)
    end
  end
end
