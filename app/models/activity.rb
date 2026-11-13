# Something the rider did, from a FIT upload or a Garmin Connect import. It
# belongs to the rider and may link to one of their completed workouts; its
# figures sit beside that workout's frozen snapshot without changing it
# (docs/adr/0002-garmin-connect-activity-import.md).
class Activity < ApplicationRecord
  POWER_METRICS = %i[average_power_watts np_watts intensity_factor tss work_kj].freeze
  MAXIMUM_FILE_SIZE = 10.megabytes
  SPORTS = %w[cycling running walking strength yoga swimming other].freeze
  # Two activities of one rider starting this close together are the same ride (GAR-005).
  DUPLICATE_WINDOW = 60.seconds

  belongs_to :user
  belongs_to :planned_workout, optional: true
  has_one_attached :ride_file

  enum :source, %w[upload garmin].index_by(&:itself), validate: true
  enum :sport, SPORTS.index_by(&:itself), validate: true
  enum :link_origin, %w[automatic rider].index_by(&:itself), prefix: :linked, validate: { allow_nil: true }

  attr_readonly :user_id

  scope :unlinked, -> { where(planned_workout_id: nil) }

  validates :planned_workout_id, uniqueness: true, allow_nil: true
  validates :garmin_activity_id, uniqueness: { scope: :user_id }, allow_nil: true
  validates :started_at, :started_on, presence: true
  validates :ride_file, presence: true, if: :upload?
  validates :ride_file, absence: { message: "is stored only for cycling" }, unless: :cycling?
  validates :link_origin, presence: true, if: :planned_workout_id
  validates :link_origin, absence: true, unless: :planned_workout_id
  validates :elapsed_seconds, :moving_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :moving_seconds, numericality: { less_than_or_equal_to: :elapsed_seconds }, if: :elapsed_seconds
  validates(*POWER_METRICS, :distance_metres, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true)
  validates :average_heart_rate_bpm, :figures_ftp_watts, numericality: { greater_than: 0 }, allow_nil: true
  validate :power_metrics_together
  validate :linked_workout_completed_and_owned

  def linked?
    planned_workout_id.present?
  end

  def power?
    !tss.nil?
  end

  def ridden_on
    started_on
  end

  def date_mismatch?
    linked? && ridden_on != planned_workout.scheduled_on
  end

  # Ridden figures from Metrics::RideCalculator. An upload's local date is
  # its start in the application time zone; Garmin supplies its own.
  def assign_metrics(result)
    assign_attributes(result.to_h.slice(:started_at, :elapsed_seconds, :moving_seconds, :average_heart_rate_bpm, *POWER_METRICS))
    self.started_on = started_at.in_time_zone.to_date if started_at && (upload? || started_on.nil?)
  end

  private

  def power_metrics_together
    missing = POWER_METRICS.map { |metric| public_send(metric).nil? }.uniq
    errors.add(:base, "Power metrics must be recorded together") if missing.size > 1
  end

  def linked_workout_completed_and_owned
    return unless planned_workout

    errors.add(:planned_workout, "must be completed") unless planned_workout.completed?
    errors.add(:planned_workout, "must belong to the same rider") unless planned_workout.training_plan.user_id == user_id
  end
end
