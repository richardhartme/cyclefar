require "rails_helper"

RSpec.describe GarminConnect::ImportActivities, type: :service do
  let(:user) { create(:user) }
  let!(:profile) do
    create(:rider_profile, user: user, ftp_watts: 260, garmin_api_key: "garmin-key", garmin_api_key_expires_on: Date.new(2027, 5, 1))
  end
  # The factory plan runs from 7 September to 29 November 2026.
  let!(:plan) { create(:training_plan, user: user, created_at: Time.utc(2026, 9, 1)) }
  let(:today) { Date.new(2026, 11, 14) }
  let(:now) { Time.utc(2026, 11, 14, 9, 30) }
  let(:client) { instance_double(GarminConnect::Client) }

  around { |example| travel_to(now) { example.run } }

  # A listed activity as the client returns it, built from a Garmin payload.
  def summary(id, start, type_key: "virtual_ride", parent_type_id: 2, utc_offset: 0, **fields)
    started_at = Time.utc(*start)
    payload = {
      "activityId" => id,
      "activityName" => "Ride #{id}",
      "startTimeGMT" => started_at.strftime("%F %T"),
      "startTimeLocal" => (started_at + utc_offset).strftime("%F %T"),
      "activityType" => { "typeId" => 152, "typeKey" => type_key, "parentTypeId" => parent_type_id },
      "distance" => 22_451.37,
      "duration" => 2712.418,
      "elapsedDuration" => 2712.418,
      "movingDuration" => 2700.0,
      "averageHR" => 140.0,
      "activityTrainingLoad" => 61.8
    }.merge(fields.transform_keys(&:to_s))
    GarminConnect::ActivitySummary.from_payload(payload)
  end

  # Lists these summaries for any window, or only for the one starting on from.
  def list(*summaries, from: nil)
    stub = allow(client).to receive(:activities)
    stub = stub.with(from: from, to: today) if from
    stub.and_return(summaries)
  end

  def import
    described_class.new(user: user, client: client).call
  end

  it "GAR-003 imports the plan's activities on the first import and records when it ran" do
    list(summary(25_012_345_678, [ 2026, 11, 10, 18, 30, 12 ], type_key: "yoga", parent_type_id: 29, utc_offset: 3600), from: plan.starts_on)

    result = import

    expect(result).to have_attributes(imported_count: 1, updated_count: 0, removed_count: 0)
    expect(user.activities.sole).to have_attributes(
      source: "garmin",
      garmin_activity_id: 25_012_345_678,
      name: "Ride 25012345678",
      sport: "yoga",
      external_type: "yoga",
      started_at: Time.utc(2026, 11, 10, 18, 30, 12),
      started_on: Date.new(2026, 11, 10),
      elapsed_seconds: 2712,
      moving_seconds: 2700,
      average_heart_rate_bpm: 140,
      planned_workout: nil)
    expect(user.activities.sole.summary).to include("activityTrainingLoad" => 61.8)
    expect(profile.reload.garmin_last_imported_at).to eq(now)
  end

  it "GAR-003 starts a later import 7 days before the last successful one" do
    profile.update!(garmin_last_imported_at: Time.utc(2026, 11, 12, 20))
    list(from: Date.new(2026, 11, 5))

    expect(import).to have_attributes(imported_count: 0, updated_count: 0, removed_count: 0)
    expect(profile.reload.garmin_last_imported_at).to eq(now)
  end

  it "GAR-004 refreshes an edited activity by its Garmin id and changes nothing on an unchanged re-run" do
    start = [ 2026, 11, 10, 18, 30, 12 ]
    list(summary(25_012_345_678, start, type_key: "yoga", parent_type_id: 29))
    import
    activity = user.activities.sole

    expect(import).to have_attributes(imported_count: 0, updated_count: 0, removed_count: 0)
    expect(activity.reload.updated_at).to eq(activity.updated_at)

    list(summary(25_012_345_678, start, type_key: "yoga", parent_type_id: 29, activityName: "Evening yoga", duration: 1800.2, elapsedDuration: 1800.2, movingDuration: 1700.4))
    expect(import).to have_attributes(imported_count: 0, updated_count: 1, removed_count: 0)
    expect(user.activities.sole).to have_attributes(id: activity.id, name: "Evening yoga", elapsed_seconds: 1800, moving_seconds: 1700)
    expect(user.activities.sole.summary).to include("activityName" => "Evening yoga")
  end

  def completed_workout(on)
    create(:planned_workout, :completed, training_plan: plan, scheduled_on: on)
  end

  def history(workout)
    workout.reload
    [ workout.attributes, workout.workout_steps.map(&:attributes), workout.workout_feedback.attributes ]
  end

  def upload(on, at)
    create(:activity, user: user, planned_workout: completed_workout(on), started_at: Time.utc(*at))
  end

  it "GAR-005 merges a Garmin ride starting within 60 seconds of an upload into it, keeping its file, figures and link" do
    uploaded = upload(Date.new(2026, 11, 10), [ 2026, 11, 10, 7, 0, 0 ])
    workout = uploaded.planned_workout
    before = history(workout)
    list(summary(25_012_345_678, [ 2026, 11, 10, 7, 1, 0 ], activityName: "Morning ride"))

    expect(import).to have_attributes(imported_count: 0, updated_count: 1, removed_count: 0)
    expect(user.activities.sole).to have_attributes(
      id: uploaded.id,
      source: "upload",
      garmin_activity_id: 25_012_345_678,
      name: "Morning ride",
      external_type: "virtual_ride",
      planned_workout: workout,
      link_origin: "rider",
      started_at: Time.utc(2026, 11, 10, 7),
      elapsed_seconds: 3660,
      tss: uploaded.tss)
    expect(user.activities.sole.summary).to include("activityName" => "Morning ride")
    expect(user.activities.sole.ride_file.download).to eq("ride")
    expect(history(workout)).to eq(before)
    expect(import).to have_attributes(imported_count: 0, updated_count: 0, removed_count: 0)
  end

  it "GAR-005 keeps a Garmin ride more than 60 seconds from an upload separate" do
    uploaded = upload(Date.new(2026, 11, 10), [ 2026, 11, 10, 7, 0, 0 ])
    list(summary(25_012_345_678, [ 2026, 11, 10, 7, 1, 1 ]))
    allow(client).to receive(:activity_file).and_raise(GarminConnect::Client::InvalidFileError)

    expect(import.imported_count).to eq(1)
    expect(uploaded.reload.garmin_activity_id).to be_nil
    expect(user.activities.garmin.sole).to have_attributes(garmin_activity_id: 25_012_345_678, planned_workout: nil)
  end

  describe "GAR-007 automatic linking" do
    before { allow(client).to receive(:activity_file).and_raise(GarminConnect::Client::InvalidFileError) }

    it "links a ride the import created to the completed workout on its date, leaving the workout unchanged" do
      workout = completed_workout(Date.new(2026, 11, 10))
      before = history(workout)
      list(summary(1, [ 2026, 11, 10, 7, 0, 0 ]))

      import

      expect(user.activities.sole).to have_attributes(planned_workout: workout, link_origin: "automatic")
      expect(history(workout)).to eq(before)
    end

    it "never links again a ride the rider unlinked, on a later import" do
      workout = completed_workout(Date.new(2026, 11, 10))
      list(summary(1, [ 2026, 11, 10, 7, 0, 0 ]))
      import
      Activities::Linker.new(user.activities.sole).unlink!

      import

      expect(user.activities.sole.planned_workout).to be_nil
      expect(workout.reload.activity).to be_nil
    end
  end

  describe "GAR-004 deletions" do
    before { profile.update!(garmin_last_imported_at: Time.utc(2026, 11, 12, 20)) }

    it "removes a Garmin-only activity Garmin no longer lists, with its link, leaving the workout unchanged" do
      ride = create(:activity, user: user, planned_workout: completed_workout(Date.new(2026, 11, 6)), source: :garmin, garmin_activity_id: 11)
      workout = ride.planned_workout
      before = history(workout)
      list(from: Date.new(2026, 11, 5))

      expect(import).to have_attributes(imported_count: 0, updated_count: 0, removed_count: 1)
      expect(Activity.exists?(ride.id)).to be(false)
      expect(history(workout)).to eq(before)
      expect(workout.reload.activity).to be_nil
    end

    it "keeps a merged upload's file and link and removes only its Garmin id and summary" do
      merged = upload(Date.new(2026, 11, 6), [ 2026, 11, 6, 7, 0, 0 ])
      merged.update!(garmin_activity_id: 12, name: "Morning ride", summary: { "activityId" => 12 })
      before = history(merged.planned_workout)
      list

      expect(import.removed_count).to eq(1)
      expect(merged.reload).to have_attributes(garmin_activity_id: nil, summary: {}, name: "Morning ride", source: "upload", planned_workout_id: merged.planned_workout_id)
      expect(merged.ride_file).to be_attached
      expect(history(merged.planned_workout)).to eq(before)
    end

    it "never touches activities outside the window or another rider's" do
      before_window = create(:activity, :unlinked, user: user, source: :garmin, sport: :yoga, garmin_activity_id: 13, started_on: Date.new(2026, 11, 4))
      other_rider = create(:activity, :unlinked, source: :garmin, sport: :yoga, garmin_activity_id: 14, started_on: Date.new(2026, 11, 10))
      list

      expect(import.removed_count).to eq(0)
      expect(Activity.where(id: [ before_window.id, other_rider.id ]).count).to eq(2)
    end
  end

  it "GAR-012 never refreshes or merges into another rider's activities" do
    theirs = create(:activity, :unlinked, source: :garmin, sport: :yoga, garmin_activity_id: 31, name: "Theirs", started_on: Date.new(2026, 11, 10))
    their_upload = create(:activity, started_at: Time.utc(2026, 11, 10, 7))
    list(summary(31, [ 2026, 11, 10, 7, 0, 30 ]))
    allow(client).to receive(:activity_file).and_raise(GarminConnect::Client::InvalidFileError)

    expect(import.imported_count).to eq(1)
    expect(user.activities.sole).to have_attributes(garmin_activity_id: 31, source: "garmin")
    expect(theirs.reload).to have_attributes(name: "Theirs", user_id: theirs.user_id)
    expect(their_upload.reload.garmin_activity_id).to be_nil
  end

  describe "GAR-003 failures" do
    it "changes nothing when the listing fails" do
      kept = create(:activity, :unlinked, user: user, source: :garmin, sport: :yoga, garmin_activity_id: 21, started_on: Date.new(2026, 11, 10))
      allow(client).to receive(:activities).and_raise(GarminConnect::Client::RemoteError)

      expect { import }.to raise_error(GarminConnect::Client::RemoteError)
      expect(Activity.exists?(kept.id)).to be(true)
      expect(profile.reload.garmin_last_imported_at).to be_nil
    end

    it "keeps what was committed before a failure, and a re-run finishes the import" do
      list(summary(22, [ 2026, 11, 10, 7, 0, 0 ]), summary(23, [ 2026, 11, 11, 7, 0, 0 ]))
      allow(client).to receive(:activity_file).with(22).and_raise(GarminConnect::Client::RateLimitedError.new(retry_after: 30))

      expect { import }.to raise_error(GarminConnect::Client::RateLimitedError)
      expect(user.activities.pluck(:garmin_activity_id)).to contain_exactly(22, 23)
      expect(profile.reload.garmin_last_imported_at).to be_nil

      allow(client).to receive(:activity_file).and_raise(GarminConnect::Client::InvalidFileError)
      expect(import).to have_attributes(imported_count: 0, updated_count: 0, removed_count: 0)
      expect(user.activities.count).to eq(2)
      expect(profile.reload.garmin_last_imported_at).to eq(now)
    end

    it "refuses to import without an active plan or a saved key" do
      allow(client).to receive(:activities)
      profile.update!(garmin_api_key: nil, garmin_api_key_expires_on: nil)
      expect { import }.to raise_error(described_class::Rejected, "Save a Garmin key in Settings before importing.")

      profile.update!(garmin_api_key: "garmin-key", garmin_api_key_expires_on: Date.new(2027, 5, 1))
      plan.update!(status: :archived)
      expect { import }.to raise_error(described_class::Rejected, "Create a training plan before importing from Garmin.")
      expect(client).not_to have_received(:activities)
    end
  end

  describe "ride files" do
    # indoor_ride.fit starts at 11:10:09 UTC on 28 October 2026.
    let(:ride_bytes) { file_fixture("fit/indoor_ride.fit").binread }
    let(:ride) { summary(1, [ 2026, 10, 28, 11, 10, 0 ]) }
    let(:yoga) { summary(2, [ 2026, 10, 28, 18, 0, 0 ], type_key: "yoga", parent_type_id: 29) }
    let(:unreadable_ride) { summary(3, [ 2026, 10, 29, 7, 0, 0 ]) }

    before do
      create(:ftp_reading, rider_profile: profile, ftp_watts: 250, effective_on: Date.new(2026, 10, 1))
      create(:ftp_reading, rider_profile: profile, ftp_watts: 280, effective_on: Date.new(2026, 11, 1))
      list(ride, yoga, unreadable_ride)
      allow(client).to receive(:activity_file).with(1).and_return(ride_bytes)
      allow(client).to receive(:activity_file).with(3).and_return("not a FIT file")
    end

    it "GAR-003 downloads files only for rides, with figures at the FTP on the ride date, and keeps a ride whose file is unreadable" do
      expect(import).to have_attributes(imported_count: 3, updated_count: 0, removed_count: 0)

      expect(client).not_to have_received(:activity_file).with(2)
      with_file = user.activities.find_by!(garmin_activity_id: 1)
      expect(with_file.ride_file.download).to eq(ride_bytes)
      expect(with_file).to have_attributes(figures_ftp_watts: 250, started_at: Time.utc(2026, 10, 28, 11, 10, 9), started_on: Date.new(2026, 10, 28))
      expect(with_file.tss).to be_present
      expect(user.activities.find_by!(garmin_activity_id: 2).ride_file).not_to be_attached
      expect(user.activities.find_by!(garmin_activity_id: 3)).to have_attributes(tss: nil, elapsed_seconds: 2712)
      expect(user.activities.find_by!(garmin_activity_id: 3).ride_file).not_to be_attached
    end

    it "GAR-003 never downloads a stored file again, and retries a file that failed" do
      import
      allow(client).to receive(:activity_file).with(3).and_raise(GarminConnect::Client::InvalidFileError)
      expect(import).to have_attributes(imported_count: 0, updated_count: 0, removed_count: 0)

      allow(client).to receive(:activity_file).with(3).and_return(ride_bytes)
      expect(import).to have_attributes(imported_count: 0, updated_count: 1, removed_count: 0)

      expect(client).to have_received(:activity_file).with(1).once
      expect(user.activities.find_by!(garmin_activity_id: 3).ride_file).to be_attached
      expect(import).to have_attributes(imported_count: 0, updated_count: 0, removed_count: 0)
    end

    it "GAR-006 drops the file and ridden figures of a ride Garmin changes to another sport" do
      import
      list(summary(1, [ 2026, 10, 28, 11, 10, 0 ], type_key: "indoor_rowing", parent_type_id: 4))

      expect(import).to have_attributes(updated_count: 1)
      changed = user.activities.find_by!(garmin_activity_id: 1)
      expect(changed).to have_attributes(sport: "other", tss: nil, figures_ftp_watts: nil, started_at: Time.utc(2026, 10, 28, 11, 10), elapsed_seconds: 2712)
      expect(changed.ride_file).not_to be_attached
    end
  end

  it "GAR-003 never starts a window before the active plan, so earlier plans' rides are left alone" do
    profile.update!(garmin_last_imported_at: Time.utc(2026, 9, 10, 20))
    list(from: plan.starts_on)

    expect(import.imported_count).to eq(0)
  end

  it "GAR-003 treats the first import after a new plan as a first import, even with a recent import for an earlier plan" do
    plan.update!(status: :archived)
    profile.update!(garmin_last_imported_at: Time.utc(2026, 11, 12, 20))
    new_plan = create(:training_plan, user: user, starts_on: Date.new(2026, 11, 2), ends_on: Date.new(2027, 1, 24))
    list(from: new_plan.starts_on)

    expect(import.imported_count).to eq(0)
  end

  it "GAR-003 asks Garmin for nothing until the active plan has started" do
    plan.update!(status: :archived)
    create(:training_plan, user: user, starts_on: today + 2, ends_on: today + 86)
    allow(client).to receive(:activities)

    expect(import).to have_attributes(imported_count: 0, updated_count: 0, removed_count: 0)
    expect(client).not_to have_received(:activities)
    expect(profile.reload.garmin_last_imported_at).to be_nil
  end
end
