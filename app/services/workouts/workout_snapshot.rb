module Workouts
  WorkoutSnapshot = Data.define(:kind, :subtype, :duration_minutes, :estimated_if, :estimated_tss)
end
