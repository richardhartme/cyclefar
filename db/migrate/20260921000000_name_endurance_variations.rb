class NameEnduranceVariations < ActiveRecord::Migration[8.1]
  def up
    rename_keys("a" => "sustained", "b" => "alternating", "c" => "undulating")
  end

  def down
    rename_keys("sustained" => "a", "alternating" => "b", "undulating" => "c")
  end

  private

  def rename_keys(mapping)
    # Completed records are protected by a database trigger and retain historical keys.
    mapping.each do |before, after|
      execute <<~SQL
        UPDATE planned_workouts
        SET variation_key = #{connection.quote(after)}
        WHERE kind = 'workout' AND subtype = 'endurance' AND status <> 'completed'
          AND variation_key = #{connection.quote(before)}
      SQL
    end
  end
end
