module Workouts
  # Attaches an uploaded FIT ride file to a completed workout, replacing any
  # earlier upload, with figures calculated at the workout's completion FTP.
  # A file matching one of the rider's existing activities links that
  # activity instead of creating a second record (GAR-005), also when it
  # replaces an earlier upload, which is then deleted.
  class RideFileAttacher
    class Rejected < StandardError; end

    CONTENT_TYPE = "application/vnd.ant.fit".freeze

    def initialize(workout:, file:)
      @workout = workout
      @file = file
      @linked_existing = false
      @replaced_upload = false
    end

    def linked_existing?
      @linked_existing
    end

    def replaced_upload?
      @replaced_upload
    end

    def call
      raise Rejected, "Choose a FIT file to upload" unless @file.respond_to?(:read)
      raise Rejected, "Ride files must be 10 MB or smaller" if @file.size > Activity::MAXIMUM_FILE_SIZE

      bytes = @file.read
      samples = Fit::Reader.new(bytes).samples

      @workout.training_plan.with_lock do
        @workout.reload
        raise Rejected, "Only completed workouts accept ride files" unless @workout.completed?
        raise Rejected, "Unlink the Garmin ride first." if @workout.activity&.garmin?

        current = @workout.activity
        activity = matching_activity(samples.first.recorded_at, replacing: current)
        if activity && current
          # The new file is a ride already stored, so the upload it replaces goes.
          current.destroy!
          @replaced_upload = true
        end
        activity ||= current || new_activity
        if @linked_existing && activity.ride_file.attached?
          Activities::Figures.new(activity).assign
        else
          activity.ride_file.attach(io: StringIO.new(bytes), filename: filename, content_type: CONTENT_TYPE)
          Activities::Figures.new(activity).assign(samples)
        end
        activity.save!
        activity
      end
    rescue Fit::Reader::InvalidFile => error
      raise Rejected, error.message
    end

    private

    def user
      @workout.training_plan.user
    end

    def new_activity
      Activity.new(user: user, planned_workout: @workout, link_origin: :rider, source: :upload, sport: :cycling)
    end

    # The closest cycling activity within the duplicate window, other than
    # the workout's own upload, unlinked ones first. Links it to this workout,
    # or rejects the upload when the ride is linked elsewhere.
    def matching_activity(started_at, replacing:)
      match = user.activities.cycling.starting_near(started_at).where.not(id: replacing)
        .min_by { |activity| [ activity.linked? ? 1 : 0, (activity.started_at - started_at).abs ] }
      return unless match

      match.lock!
      if (other = match.planned_workout)
        linked_to = "This ride is already linked to #{other.name} on #{other.scheduled_on.to_fs(:long)}"
        raise Rejected, "#{linked_to} in an archived plan." if other.training_plan.archived?
        # Change ride isn't offered while an upload is linked.
        raise Rejected, "#{linked_to}. Remove this ride file, then use Choose ride to move it." if replacing
        raise Rejected, "#{linked_to}. Use Change ride to move it."
      end

      @linked_existing = true
      match.assign_attributes(planned_workout: @workout, link_origin: :rider)
      match
    end

    def filename
      name = @file.respond_to?(:original_filename) ? @file.original_filename.presence : nil
      name || "ride.fit"
    end
  end
end
