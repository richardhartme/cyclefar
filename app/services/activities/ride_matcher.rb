module Activities
  # Decides which of a rider's rides belong to which completed workout
  # (GAR-007–GAR-009). Every link it makes runs under the workout's plan
  # lock, the same lock ride uploads take, so two writers never race for one
  # workout. Linking writes only the activity (Activities::Linker); the
  # completed workout's snapshot and feedback never change.
  class RideMatcher
    class Rejected < StandardError; end

    # The picker offers rides this many days either side of the workout.
    PICKER_DAYS = 3

    def initialize(user)
      @user = user
    end

    # After a workout is completed, links the preselected ride the rider
    # chose from Ride found, or else the one unlinked ride on its date. Call
    # it inside the completion's plan lock.
    def link_after_completion!(workout, ride: nil)
      if ride
        ride.reload
        raise Rejected, "That ride is already linked to another workout." if ride.linked?
        raise Rejected, "Only rides can be linked to a workout." unless ride.cycling? && ride.user_id == @user.id
        raise Rejected, "Only a ride on the workout's date can be linked as it is completed." unless ride.started_on == workout.scheduled_on

        Linker.new(ride).link!(workout, origin: :rider)
      else
        auto_link(workout.training_plan, workout.scheduled_on)
      end
    end

    # After an import, links rides the import created, and only those, so a
    # ride the rider unlinked is never linked again. An older unlinked ride on
    # the same date makes two candidates, so nothing links there.
    def link_imported!(created)
      plan = @user.training_plans.active.first
      return unless plan

      created.select(&:cycling?).map(&:started_on).uniq.each do |date|
        plan.with_lock { auto_link(plan, date, only: created) }
      end
    end

    # Rides the rider may choose for a completed workout: cycling activities
    # within 3 days of its date, newest first, that are unlinked or linked to
    # another workout in the active plan. Archived plans' rides are history.
    def candidates(workout)
      dates = (workout.scheduled_on - PICKER_DAYS)..(workout.scheduled_on + PICKER_DAYS)
      rides = @user.activities.cycling.where(started_on: dates).left_joins(planned_workout: :training_plan)
      rides.unlinked
        .or(rides.where(training_plans: { status: :active }).where.not(planned_workout_id: workout.id))
        .includes(:planned_workout)
        .order(started_at: :desc, id: :desc)
        .to_a
    end

    # Links the ride the rider chose, moving it from another workout or
    # replacing the workout's Garmin ride in one transaction.
    def choose!(workout, activity)
      workout.training_plan.with_lock do
        workout.reload
        raise Rejected, "Only completed workouts take a ride." unless workout.completed?
        raise Rejected, "Choose a ride within #{PICKER_DAYS} days of this workout." unless candidates(workout).include?(activity)

        current = workout.activity
        if current
          raise Rejected, "Remove the uploaded ride file first." if current.upload?

          Linker.new(current).unlink!
        end
        Linker.new(activity).link!(workout, origin: :rider)
      end
    rescue ActiveRecord::RecordNotUnique
      raise Rejected, "This workout already has a ride. Reload the page and try again."
    end

    # Unlinked rides by date, newest first, for the Ride found prompt on
    # planned workouts. Nothing here completes a workout.
    def found_rides(dates)
      unlinked_rides_on(dates).order(started_at: :desc, id: :desc).group_by(&:started_on)
    end

    private

    def unlinked_rides_on(dates)
      @user.activities.unlinked.cycling.where(started_on: dates)
    end

    # Links the one unlinked ride on a date to the plan's completed workout
    # there, when that workout has no ride yet.
    def auto_link(plan, date, only: nil)
      workout = plan.planned_workouts.completed.where.missing(:activity).find_by(scheduled_on: date)
      rides = unlinked_rides_on(date).to_a
      return unless workout && rides.one?
      return if only && !only.include?(rides.first)

      Linker.new(rides.first).link!(workout, origin: :automatic)
    end
  end
end
