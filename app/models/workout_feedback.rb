class WorkoutFeedback < ApplicationRecord
  belongs_to :planned_workout
  include ProtectsCompletedWorkout

  enum :completion_quality, %w[as_planned struggled_completed could_not_complete].index_by(&:itself), validate: true
  validates :planned_workout_id, uniqueness: true
  validates :rpe, numericality: { only_integer: true, in: 1..10 }
end
