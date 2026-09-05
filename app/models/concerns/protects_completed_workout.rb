module ProtectsCompletedWorkout
  extend ActiveSupport::Concern

  included do
    validate :parent_workout_is_editable
    before_destroy :prevent_completed_child_destruction
  end

  private

  def completed_parent?
    ids = [ planned_workout_id, planned_workout_id_in_database ].compact.uniq
    PlannedWorkout.where(id: ids, status: "completed").exists?
  end

  def parent_workout_is_editable
    errors.add(:base, "Completed workout history is immutable") if completed_parent?
  end

  def prevent_completed_child_destruction
    if completed_parent?
      errors.add(:base, "Completed workout history is immutable")
      throw :abort
    end
  end
end
