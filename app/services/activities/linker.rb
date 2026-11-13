module Activities
  # Links, unlinks and relinks an activity, recalculating its ridden figures
  # in the same transaction. Only the activity row is written: the completed
  # workout's structure, snapshot and feedback never change (FBK-004, GAR-008).
  class Linker
    def initialize(activity)
      @activity = activity
    end

    # Moves an already linked activity in one step, leaving its previous
    # workout without a ride.
    def link!(workout, origin:)
      change { @activity.assign_attributes(planned_workout: workout, link_origin: origin) }
    end

    def unlink!
      change { @activity.assign_attributes(planned_workout: nil, link_origin: nil) }
    end

    def recalculate!
      change { }
    end

    private

    def change
      @activity.transaction do
        @activity.lock!
        yield
        Figures.new(@activity).assign
        @activity.save!
      end
      @activity
    end
  end
end
