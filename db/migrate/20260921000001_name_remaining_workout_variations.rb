class NameRemainingWorkoutVariations < ActiveRecord::Migration[8.1]
  def up
    rename_keys("kind = 'workout' AND subtype = 'recovery'", "a" => "steady", "b" => "gentle_ramp")
    rename_keys("kind = 'workout' AND subtype NOT IN ('recovery', 'endurance')", "a" => "standard", "b" => "redistributed_recovery")
    rename_keys("kind = 'opener'", "a" => "activation")
  end

  def down
    rename_keys("kind = 'workout' AND subtype = 'recovery'", "steady" => "a", "gentle_ramp" => "b")
    rename_keys("kind = 'workout' AND subtype NOT IN ('recovery', 'endurance')", "standard" => "a", "redistributed_recovery" => "b")
    rename_keys("kind = 'opener'", "activation" => "a")
  end

  private

  def rename_keys(condition, mapping)
    # Preserve immutable completed history and all saved workout structures.
    mapping.each do |before, after|
      execute <<~SQL
        UPDATE planned_workouts
        SET variation_key = #{connection.quote(after)}
        WHERE #{condition} AND status <> 'completed'
          AND variation_key = #{connection.quote(before)}
      SQL
    end
  end
end
