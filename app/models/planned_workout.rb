class PlannedWorkout < ApplicationRecord
  METRICS = %i[estimated_np_watts estimated_if estimated_tss estimated_work_kj].freeze

  belongs_to :training_plan
  belongs_to :plan_phase, optional: true
  has_many :workout_steps, -> { order(:position) }, dependent: :destroy, autosave: true
  has_one :workout_feedback, dependent: :destroy, autosave: true
  has_one :intervals_icu_sync, dependent: :nullify

  enum :kind, %w[workout opener].index_by(&:itself), validate: true
  enum :intent, AvailabilitySlot::INTENTS.index_by(&:itself), prefix: true, validate: { allow_nil: true }
  enum :subtype, %w[recovery endurance tempo sweet_spot threshold vo2_max over_under].index_by(&:itself), prefix: true, validate: { allow_nil: true }
  enum :detail_status, %w[outline structured].index_by(&:itself), validate: true
  enum :status, %w[planned missed completed].index_by(&:itself), validate: true

  validates :scheduled_on, presence: true, uniqueness: { scope: :training_plan_id }
  validates :intent, presence: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 30 }
  validates :progression_level, numericality: { only_integer: true, in: 1..7 }, allow_nil: true
  validates(*METRICS, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true)
  validates :completed_at, presence: true, if: :completed?
  validates :completed_ftp_watts, numericality: { only_integer: true, greater_than: 0 }, if: :completed?
  validates :completed_at, :completed_ftp_watts, :completed_target_snapshot, absence: true, if: -> { planned? || missed? }
  validate :generation_context_is_object
  validate :schedule_matches_plan
  validate :canonical_structure
  validate :completion_has_snapshot

  def readonly?
    (persisted? && status_in_database == "completed") || super
  end

  def assign_metrics(metrics)
    METRICS.each { |key| public_send("#{key}=", metrics&.public_send(key)) }
  end

  # Replaces the steps with canonical definitions; the caller saves.
  def replace_steps(step_definitions)
    workout_steps.destroy_all
    step_definitions.each { |step| workout_steps.build(step.to_h) }
  end

  # The one path that persists a generated definition onto a workout. Extra
  # attributes override the definition-derived ones. Callers save.
  def apply_definition(definition, metrics, structured: true, track_generation: false, baseline_level: nil, **attributes)
    context = attributes.delete(:generation_context) || generation_context
    if track_generation
      context = context.merge(
        "generated_level" => definition.progression_level,
        "generated_tss" => metrics.estimated_tss,
        "load_adjustments" => definition.load_adjustments)
      context["baseline_level"] = baseline_level if baseline_level
    end
    assign_attributes({
      detail_status: structured ? :structured : :outline,
      subtype: definition.subtype,
      duration_minutes: definition.duration_minutes,
      progression_level: definition.progression_level,
      variation_key: definition.variation_key,
      name: definition.name,
      purpose: definition.purpose,
      generation_context: context
    }.merge(attributes))
    assign_metrics(metrics)
    replace_steps(structured ? definition.steps : [])
  end

  private

  def generation_context_is_object
    errors.add(:generation_context, "must be an object") unless generation_context.is_a?(Hash)
  end

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
    if structured?
      errors.add(:workout_steps, "must exactly match the workout duration") if steps.empty? || steps.sum { |step| step.duration_seconds.to_i } != duration_minutes.to_i * 60
    elsif steps.any?
      errors.add(:workout_steps, "must be absent for an outline workout")
    end
  end

  def completion_has_snapshot
    return unless completed?

    errors.add(:detail_status, "must be structured before completion") unless structured?
    unless completed_target_snapshot.is_a?(Hash) && completed_target_snapshot.present?
      errors.add(:completed_target_snapshot, "must contain the frozen watt targets and metrics")
    end
  end
end
