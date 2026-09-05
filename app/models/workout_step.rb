class WorkoutStep < ApplicationRecord
  belongs_to :planned_workout
  include ProtectsCompletedWorkout
  enum :kind, %w[steady ramp].index_by(&:itself), validate: true

  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :planned_workout_id }
  validates :label, presence: true
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :target_low_pct_ftp, :target_high_pct_ftp, numericality: { greater_than: 0 }
  validates :target_high_pct_ftp, comparison: { greater_than_or_equal_to: :target_low_pct_ftp }, if: -> { target_low_pct_ftp && target_high_pct_ftp }
  validates :end_target_low_pct_ftp, :end_target_high_pct_ftp, numericality: { greater_than: 0 }, if: :ramp?
  validates :end_target_high_pct_ftp, comparison: { greater_than_or_equal_to: :end_target_low_pct_ftp }, if: -> { ramp? && end_target_low_pct_ftp && end_target_high_pct_ftp }
  validates :end_target_low_pct_ftp, :end_target_high_pct_ftp, absence: true, if: :steady?
  validates :group_iteration, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
