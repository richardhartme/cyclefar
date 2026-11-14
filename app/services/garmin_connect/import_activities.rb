module GarminConnect
  # Imports the Garmin rider's activities for the active plan's dates
  # (GAR-003–GAR-005, docs/GARMIN_CONNECT.md#reconciliation). Each activity
  # commits in its own short transaction and no transaction spans HTTP, so a
  # failure keeps what was committed and a re-run is safe.
  class ImportActivities
    # Later imports look back this far, to catch rides edited or deleted since.
    LOOKBACK = 7.days
    Result = Data.define(:imported_count, :updated_count, :removed_count)

    # The import can't start; nothing was asked of Garmin.
    class Rejected < StandardError; end

    def initialize(user:, client: nil)
      @user = user
      @client = client
    end

    def call
      OwnerLock.hold(@user, "garmin-connect") { import }
    end

    private

    def import
      profile = @user.rider_profile
      raise Rejected, "Save a Garmin key in Settings before importing." if profile&.garmin_api_key.blank?

      plan = @user.training_plans.active.first
      raise Rejected, "Create a training plan before importing from Garmin." unless plan

      started_at = Time.current
      window = window_for(plan, profile)
      return Result.new(imported_count: 0, updated_count: 0, removed_count: 0) if window.none?

      client = @client || Client.new(api_key: profile.garmin_api_key)

      summaries = client.activities(from: window.begin, to: window.end)
      outcomes = summaries.map { |summary| upsert(summary) }
      removed_count = remove_missing(window, summaries.map(&:garmin_activity_id))
      outcomes.each do |outcome|
        outcome[:result] = :updated if attach_file(client, outcome[:activity]) && outcome[:result] == :unchanged
      end
      profile.update!(garmin_last_imported_at: started_at)
      results = outcomes.pluck(:result)
      Result.new(imported_count: results.count(:imported), updated_count: results.count(:updated), removed_count: removed_count)
    end

    # The plan's start on the plan's first import, then 7 days before the
    # last successful one, never before the plan's start: earlier plans'
    # rides are history (ADR 0002). Empty until the plan starts.
    def window_for(plan, profile)
      last_imported_at = profile.garmin_last_imported_at
      from = plan.starts_on
      from = [ from, (last_imported_at - LOOKBACK).in_time_zone.to_date ].max if last_imported_at && last_imported_at > plan.created_at
      from..Date.current
    end

    # Creates or refreshes one activity, and says whether it was :imported,
    # :updated or :unchanged.
    def upsert(summary)
      Activity.transaction do
        activity = @user.activities.lock.find_by(garmin_activity_id: summary.garmin_activity_id) ||
          matching_upload(summary) ||
          @user.activities.new(source: :garmin)
        activity.upload? ? merge(activity, summary) : refresh(activity, summary)
        result = if activity.new_record? then :imported elsif activity.changed? then :updated else :unchanged end
        activity.save!
        { activity: activity, result: result }
      end
    end

    # The closest upload starting within the duplicate window that has no
    # Garmin id yet. Only rides merge, as only rides match an upload (GAR-005).
    def matching_upload(summary)
      return unless summary.sport == "cycling"

      @user.activities.upload.cycling.where(garmin_activity_id: nil).starting_near(summary.started_at).lock
        .min_by { |activity| (activity.started_at - summary.started_at).abs }
    end

    # An upload keeps its source, file, figures and link, and gains Garmin's
    # id, name, type and summary.
    def merge(activity, summary)
      activity.assign_attributes(
        garmin_activity_id: summary.garmin_activity_id, name: summary.name, external_type: summary.external_type, summary: summary.payload)
    end

    # A stored file's figures win over the summary's, so a re-run with an
    # unchanged summary changes nothing.
    def refresh(activity, summary)
      activity.assign_attributes(
        garmin_activity_id: summary.garmin_activity_id,
        name: summary.name,
        external_type: summary.external_type,
        sport: summary.sport,
        started_on: summary.started_on,
        distance_metres: summary.distance_metres,
        summary: summary.payload)
      drop_ride_file(activity) if activity.ride_file.attached? && !activity.cycling?
      return if activity.ride_file.attached?

      elapsed_seconds = summary.elapsed_seconds || summary.duration_seconds || 0
      activity.assign_attributes(
        started_at: summary.started_at,
        elapsed_seconds: elapsed_seconds,
        moving_seconds: [ summary.moving_seconds || elapsed_seconds, elapsed_seconds ].min,
        average_heart_rate_bpm: summary.average_heart_rate_bpm&.positive? ? summary.average_heart_rate_bpm : nil)
    end

    # A complete listing that no longer returns a stored activity means it
    # was deleted in Garmin. A Garmin-only record goes, with its link and
    # file; a merged upload keeps them and loses only Garmin's id and summary.
    def remove_missing(window, listed_ids)
      missing = @user.activities.where(started_on: window).where.not(garmin_activity_id: nil).where.not(garmin_activity_id: listed_ids)
      missing.find_each.count do |activity|
        Activity.transaction do
          activity.lock!
          activity.garmin? ? activity.destroy! : activity.update!(garmin_activity_id: nil, summary: {})
        end
      end
    end

    # Only rides keep a file and ridden figures (GAR-006). The file is
    # purged once the activity saves.
    def drop_ride_file(activity)
      activity.ride_file = nil
      activity.assign_attributes(Activity::POWER_METRICS.index_with(nil).merge(figures_ftp_watts: nil))
    end

    # Downloads and stores a ride's original file once, with its figures.
    # An unreadable file leaves the ride without one, for the next import to
    # retry; any other client error ends the import.
    def attach_file(client, activity)
      return false unless activity.cycling? && !activity.ride_file.attached?

      bytes = client.activity_file(activity.garmin_activity_id)
      samples = Fit::Reader.new(bytes).samples
      Activity.transaction do
        activity.lock!
        activity.ride_file.attach(io: StringIO.new(bytes), filename: "garmin-#{activity.garmin_activity_id}.fit", content_type: Workouts::RideFileAttacher::CONTENT_TYPE)
        Activities::Figures.new(activity).assign(samples)
        activity.save!
      end
      true
    rescue Client::InvalidFileError, Fit::Reader::InvalidFile
      false
    end
  end
end
