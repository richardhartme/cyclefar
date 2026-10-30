# Ridden metrics from an uploaded FIT file. They sit beside a completed
# workout's frozen snapshot without changing it, so replacing or removing them
# is allowed (docs/adr/0001-ride-file-upload-for-completed-workouts.md).
class WorkoutActivity < ApplicationRecord
  POWER_METRICS = %i[average_power_watts np_watts intensity_factor tss work_kj].freeze
  MAXIMUM_FILE_SIZE = 10.megabytes

  belongs_to :planned_workout
  has_one_attached :ride_file

  attr_readonly :planned_workout_id

  validates :planned_workout_id, uniqueness: true
  validates :started_at, :ride_file, presence: true
  validates :elapsed_seconds, :moving_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :moving_seconds, numericality: { less_than_or_equal_to: :elapsed_seconds }, if: :elapsed_seconds
  validates(*POWER_METRICS, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true)
  validates :average_heart_rate_bpm, numericality: { greater_than: 0 }, allow_nil: true
  validate :power_metrics_together
  validate :planned_workout_completed

  def power?
    !tss.nil?
  end

  def ridden_on
    started_at.in_time_zone.to_date
  end

  def date_mismatch?
    ridden_on != planned_workout.scheduled_on
  end

  def assign_metrics(result)
    assign_attributes(result.to_h.slice(:started_at, :elapsed_seconds, :moving_seconds, :average_heart_rate_bpm, *POWER_METRICS))
  end

  private

  def power_metrics_together
    missing = POWER_METRICS.map { |metric| public_send(metric).nil? }.uniq
    errors.add(:base, "Power metrics must be recorded together") if missing.size > 1
  end

  def planned_workout_completed
    errors.add(:planned_workout, "must be completed") unless planned_workout&.completed?
  end
end
