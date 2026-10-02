class AddWorkoutGenerationContext < ActiveRecord::Migration[8.1]
  def change
    add_column :planned_workouts, :generation_context, :jsonb, default: {}, null: false
    add_check_constraint :planned_workouts, "jsonb_typeof(generation_context) = 'object'", name: "planned_workouts_generation_context_object"
  end
end
