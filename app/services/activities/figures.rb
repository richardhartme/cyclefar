module Activities
  # Ridden figures for a cycling activity from its FIT samples: at the linked
  # workout's frozen completion FTP, or, when unlinked, at the FTP in force on
  # the ride's local date (FBK-004). Assigns only; the caller saves.
  class Figures
    def initialize(activity)
      @activity = activity
    end

    # Samples default to the stored file. Without a file there is nothing to
    # calculate and the activity keeps the figures it has.
    def assign(samples = stored_samples)
      return @activity if samples.nil?

      # An upload's local date comes from the file, and an unlinked ride's FTP
      # from that date.
      @activity.assign_metrics(started_at: samples.first.recorded_at)
      ftp_watts = applicable_ftp_watts
      @activity.assign_metrics(Metrics::RideCalculator.new(samples: samples, ftp_watts: ftp_watts).call)
      @activity.figures_ftp_watts = ftp_watts
      @activity
    end

    def current?
      !recalculable? || @activity.figures_ftp_watts == applicable_ftp_watts
    end

    private

    def recalculable?
      @activity.cycling? && @activity.ride_file.attached?
    end

    def stored_samples
      Fit::Reader.new(@activity.ride_file.download).samples if recalculable?
    end

    def applicable_ftp_watts
      if @activity.planned_workout
        @activity.planned_workout.completed_ftp_watts
      else
        @activity.user.rider_profile&.ftp_watts_on(@activity.started_on)
      end
    end
  end
end
