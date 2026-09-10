class PlannedWorkout < ApplicationRecord
  METRICS = %i[estimated_np_watts estimated_if estimated_tss estimated_work_kj].freeze

  belongs_to :training_plan
  belongs_to :plan_phase, optional: true
  has_many :workout_steps, -> { order(:position) }, dependent: :destroy, autosave: true
  has_one :workout_feedback, dependent: :destroy, autosave: true
  has_one :intervals_icu_sync, dependent: :nullify

  enum :kind, %w[workout ftp_test opener].index_by(&:itself), validate: true
  enum :intent, AvailabilitySlot::INTENTS.index_by(&:itself), prefix: true, validate: { allow_nil: true }
  enum :subtype, %w[recovery endurance tempo sweet_spot threshold vo2_max over_under].index_by(&:itself), prefix: true, validate: { allow_nil: true }
  enum :detail_status, %w[outline structured].index_by(&:itself), validate: true
  enum :status, %w[planned missed completed].index_by(&:itself), validate: true

  validates :scheduled_on, presence: true, uniqueness: { scope: :training_plan_id }
  validates :intent, presence: true, unless: :ftp_test?
  validates :duration_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 30 }, unless: :ftp_test?
  validates :progression_level, numericality: { only_integer: true, in: 1..7 }, allow_nil: true
  validates(*METRICS, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true)
  validates :completed_at, presence: true, if: :completed?
  validates :completed_ftp_watts, numericality: { only_integer: true, greater_than: 0 }, if: -> { completed? && !ftp_test? }
  validates :completed_at, :completed_ftp_watts, :completed_target_snapshot, absence: true, if: -> { planned? || missed? }
  validate :schedule_matches_plan
  validate :canonical_structure
  validate :completion_has_snapshot

  def readonly?
    (persisted? && status_in_database == "completed") || super
  end

  private

  def schedule_matches_plan
    if training_plan&.starts_on && training_plan.ends_on && scheduled_on
      errors.add(:scheduled_on, "must be within the plan") unless scheduled_on.between?(training_plan.starts_on, training_plan.ends_on)
    end
    if plan_phase && (plan_phase.training_plan != training_plan || !scheduled_on&.between?(plan_phase.starts_on, plan_phase.ends_on))
      errors.add(:plan_phase, "must belong to this plan and contain the workout date")
    end
  end

  def canonical_structure
    steps = workout_steps.reject(&:marked_for_destruction?)
    if ftp_test?
      errors.add(:base, "FTP tests have no prescribed protocol or metrics") if structured? || duration_minutes || METRICS.any? { |metric| public_send(metric) } || steps.any?
    elsif structured?
      errors.add(:workout_steps, "must exactly match the workout duration") if steps.empty? || steps.sum { |step| step.duration_seconds.to_i } != duration_minutes.to_i * 60
    elsif steps.any?
      errors.add(:workout_steps, "must be absent for an outline workout")
    end
  end

  def completion_has_snapshot
    return unless completed? && !ftp_test?

    errors.add(:detail_status, "must be structured before completion") unless structured?
    unless completed_target_snapshot.is_a?(Hash) && completed_target_snapshot.present?
      errors.add(:completed_target_snapshot, "must contain the frozen watt targets and metrics")
    end
  end
end
