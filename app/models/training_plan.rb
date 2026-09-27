class TrainingPlan < ApplicationRecord
  GOALS = %w[general_fitness increase_ftp improve_endurance improve_climbing event].freeze
  DISCIPLINES = %w[road gravel mtb ultra_endurance].freeze
  CONFIGURATION_ATTRIBUTES = %w[goal discipline starts_on ends_on include_base progression_mode hard_weeks_before_recovery initial_ftp_watts engine_version].freeze

  enum :status, %w[active archived].index_by(&:itself), validate: true
  enum :goal, GOALS.index_by(&:itself), validate: true
  enum :discipline, DISCIPLINES.index_by(&:itself), validate: true
  enum :progression_mode, %w[continuous hard_recovery_cycle].index_by(&:itself), validate: true

  belongs_to :user
  has_many :planned_workouts, dependent: :destroy
  has_one :target_event, dependent: :destroy
  has_many :plan_phases, -> { order(:position) }, dependent: :destroy
  has_many :availability_templates, dependent: :destroy
  has_many :time_off_periods, dependent: :destroy
  has_many :adaptation_proposals, dependent: :destroy

  validates :status, uniqueness: { scope: :user_id }, if: :active?
  validates :starts_on, :ends_on, :engine_version, presence: true
  validates :ends_on, comparison: { greater_than_or_equal_to: :starts_on }, if: -> { starts_on && ends_on }
  validates :include_base, inclusion: { in: [ true, false ] }
  validates :initial_ftp_watts, numericality: { only_integer: true, greater_than: 0 }
  validates :hard_weeks_before_recovery, numericality: { only_integer: true, greater_than: 0 }, if: :hard_recovery_cycle?
  validates :hard_weeks_before_recovery, absence: true, if: :continuous?
  validate :progression_state_is_object
  validate :configuration_is_immutable, on: :update
  before_destroy :preserve_completed_history, prepend: true

  def ftp_watts_for_planning
    user.rider_profile&.ftp_watts || initial_ftp_watts
  end

  private

  def progression_state_is_object
    errors.add(:progression_state, "must be an object") unless progression_state.is_a?(Hash)
  end

  def configuration_is_immutable
    if (changes.keys & CONFIGURATION_ATTRIBUTES).any?
      errors.add(:base, "Confirmed plan configuration cannot be changed")
    end
  end

  def preserve_completed_history
    if planned_workouts.completed.exists?
      errors.add(:base, "Plans with completed workouts must be kept as history")
      throw :abort
    end
  end
end
