require "rails_helper"

RSpec.describe Activities::RideMatcher, type: :service do
  let(:user) { create(:user) }
  # The factory plan runs from 7 September to 29 November 2026.
  let(:plan) { create(:training_plan, user: user) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:matcher) { described_class.new(user) }

  def completed(on)
    create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: on, name: "Ride on #{on.day}")
  end

  def ride(on, hour: 7, **attributes)
    create(:activity, :unlinked, :garmin, user: user, started_at: on.in_time_zone.change(hour: hour), started_on: on, **attributes)
  end

  def history(workout)
    workout.reload
    [ workout.attributes, workout.workout_steps.map(&:attributes), workout.workout_feedback.attributes ]
  end

  describe "GAR-007 linking after completion" do
    let(:date) { Date.new(2026, 9, 10) }

    it "links the one unlinked ride on the workout's date automatically" do
      workout = completed(date)
      found = ride(date)
      before = history(workout)

      expect(matcher.link_after_completion!(workout)).to eq(found)

      expect(found.reload).to have_attributes(planned_workout: workout, link_origin: "automatic")
      expect(history(workout)).to eq(before)
    end

    it "links nothing when there is no ride on the date" do
      workout = completed(date)
      ride(date + 1)

      expect(matcher.link_after_completion!(workout)).to be_nil
      expect(workout.reload.activity).to be_nil
    end

    it "keeps two rides on one day separate" do
      workout = completed(date)
      rides = [ ride(date, hour: 7), ride(date, hour: 17) ]

      expect(matcher.link_after_completion!(workout)).to be_nil
      expect(rides.map { |activity| activity.reload.planned_workout }).to all(be_nil)
    end

    it "considers only cycling activities" do
      workout = completed(date)
      run = ride(date, sport: :running, average_power_watts: nil, np_watts: nil, intensity_factor: nil, tss: nil, work_kj: nil)

      expect(matcher.link_after_completion!(workout)).to be_nil
      expect(run.reload.planned_workout).to be_nil
    end

    it "never replaces an existing link" do
      workout = completed(date)
      uploaded = create(:activity, user: user, planned_workout: workout)
      found = ride(date)

      expect(matcher.link_after_completion!(workout)).to be_nil
      expect(uploaded.reload).to have_attributes(planned_workout: workout, link_origin: "rider")
      expect(found.reload.planned_workout).to be_nil
    end

    it "links a preselected ride for the rider instead, even beside another ride" do
      workout = completed(date)
      ride(date, hour: 7)
      chosen = ride(date, hour: 17)

      expect(matcher.link_after_completion!(workout, ride: chosen)).to eq(chosen)
      expect(chosen.reload).to have_attributes(planned_workout: workout, link_origin: "rider")
    end

    it "refuses a preselected ride that is already linked" do
      workout = completed(date)
      taken = ride(date - 1)
      Activities::Linker.new(taken).link!(completed(date - 1), origin: :rider)

      expect { matcher.link_after_completion!(workout, ride: taken) }.to raise_error(described_class::Rejected, /already linked/)
    end
  end

  describe "GAR-007 linking after an import" do
    let(:date) { Date.new(2026, 9, 10) }

    it "links a ride the import created to the completed workout on its date" do
      workout = completed(date)
      created = ride(date)

      expect(matcher.link_imported!([ created ])).to eq(1)
      expect(created.reload).to have_attributes(planned_workout: workout, link_origin: "automatic")
    end

    it "leaves alone rides the import did not create, so an unlinked ride stays unlinked" do
      completed(date)
      unlinked_by_rider = ride(date)

      expect(matcher.link_imported!([])).to eq(0)
      expect(unlinked_by_rider.reload.planned_workout).to be_nil
    end

    it "links nothing when an older unlinked ride shares the date" do
      completed(date)
      ride(date, hour: 7)
      created = ride(date, hour: 17)

      expect(matcher.link_imported!([ created ])).to eq(0)
      expect(created.reload.planned_workout).to be_nil
    end

    it "links nothing to planned workouts, linked workouts or archived plans" do
      create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: date)
      linked_day = date + 1
      create(:activity, user: user, planned_workout: completed(linked_day))
      archived = create(:training_plan, :archived, user: user, starts_on: Date.new(2026, 6, 1), ends_on: Date.new(2026, 8, 30))
      archived_phase = create(:plan_phase, training_plan: archived, ends_on: archived.ends_on)
      create(:planned_workout, :completed, training_plan: archived, plan_phase: archived_phase, scheduled_on: Date.new(2026, 6, 2))
      plan
      created = [ ride(date), ride(linked_day), ride(Date.new(2026, 6, 2)) ]

      expect(matcher.link_imported!(created)).to eq(0)
      expect(created.map { |activity| activity.reload.planned_workout }).to all(be_nil)
    end
  end

  describe "GAR-008 Choose ride candidates" do
    let(:date) { Date.new(2026, 9, 16) }

    it "lists cycling rides within 3 days either side, newest first, with rides linked elsewhere in the active plan" do
      workout = completed(date)
      elsewhere = completed(date - 2)
      linked_elsewhere = ride(date - 2)
      Activities::Linker.new(linked_elsewhere).link!(elsewhere, origin: :automatic)
      early = ride(date - 3)
      late = ride(date + 3, hour: 6)
      same_day = ride(date, hour: 18)
      ride(date - 4)
      ride(date + 4)
      ride(date, sport: :yoga, average_power_watts: nil, np_watts: nil, intensity_factor: nil, tss: nil, work_kj: nil)
      create(:activity, :unlinked, :garmin, started_on: date)

      expect(matcher.candidates(workout)).to eq([ late, same_day, linked_elsewhere, early ])
    end

    it "leaves out the workout's own ride and rides linked in archived plans" do
      workout = completed(date)
      own = ride(date)
      Activities::Linker.new(own).link!(workout, origin: :automatic)
      archived = create(:training_plan, :archived, user: user, starts_on: Date.new(2026, 6, 1), ends_on: Date.new(2026, 8, 30))
      archived_phase = create(:plan_phase, training_plan: archived, ends_on: archived.ends_on)
      history = create(:planned_workout, :completed, training_plan: archived, plan_phase: archived_phase, scheduled_on: Date.new(2026, 8, 1))
      archived_ride = ride(date + 1)
      Activities::Linker.new(archived_ride).link!(history, origin: :rider)

      expect(matcher.candidates(workout)).to be_empty
    end
  end

  describe "GAR-008 choosing a ride" do
    let(:date) { Date.new(2026, 9, 16) }

    it "links an unlinked ride the rider chose" do
      workout = completed(date)
      chosen = ride(date + 1)
      before = history(workout)

      matcher.choose!(workout, chosen)

      expect(chosen.reload).to have_attributes(planned_workout: workout, link_origin: "rider")
      expect(history(workout)).to eq(before)
    end

    it "moves a ride linked elsewhere in one transaction, leaving that workout without a ride" do
      workout = completed(date)
      elsewhere = completed(date - 1)
      moving = ride(date - 1)
      Activities::Linker.new(moving).link!(elsewhere, origin: :automatic)
      before = [ history(workout), history(elsewhere) ]

      matcher.choose!(workout, moving)

      expect(moving.reload).to have_attributes(planned_workout: workout, link_origin: "rider")
      expect(elsewhere.reload.activity).to be_nil
      expect([ history(workout), history(elsewhere) ]).to eq(before)
    end

    it "changes the ride, keeping the Garmin ride it replaces as an unlinked activity" do
      workout = completed(date)
      current = ride(date)
      Activities::Linker.new(current).link!(workout, origin: :automatic)
      replacement = ride(date, hour: 18)

      matcher.choose!(workout, replacement)

      expect(replacement.reload.planned_workout).to eq(workout)
      expect(current.reload).to have_attributes(planned_workout: nil, link_origin: nil)
    end

    it "refuses to change away from an uploaded ride" do
      workout = completed(date)
      uploaded = create(:activity, user: user, planned_workout: workout)
      replacement = ride(date)

      expect { matcher.choose!(workout, replacement) }.to raise_error(described_class::Rejected, "Remove the uploaded ride file first.")
      expect(uploaded.reload.planned_workout).to eq(workout)
      expect(replacement.reload.planned_workout).to be_nil
    end

    it "refuses rides that are not candidates" do
      workout = completed(date)
      too_far = ride(date + 4)
      run = ride(date, sport: :running, average_power_watts: nil, np_watts: nil, intensity_factor: nil, tss: nil, work_kj: nil)

      [ too_far, run ].each do |activity|
        expect { matcher.choose!(workout, activity) }.to raise_error(described_class::Rejected, "Choose a ride within 3 days of this workout.")
        expect(activity.reload.planned_workout).to be_nil
      end
    end

    it "refuses workouts that are not completed" do
      planned = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: date)
      activity = ride(date)

      expect { matcher.choose!(planned, activity) }.to raise_error(described_class::Rejected, "Only completed workouts take a ride.")
    end

    it "GAR-012 refuses another rider's ride" do
      workout = completed(date)
      someone_elses = create(:activity, :unlinked, :garmin, started_on: date)

      expect { matcher.choose!(workout, someone_elses) }.to raise_error(described_class::Rejected)
      expect(someone_elses.reload.planned_workout).to be_nil
    end

    it "turns a link that loses a race into a readable rejection" do
      workout = completed(date)
      chosen = ride(date)
      allow(Activities::Linker).to receive(:new).and_wrap_original do |original, activity|
        original.call(activity).tap { |linker| allow(linker).to receive(:link!).and_raise(ActiveRecord::RecordNotUnique) }
      end

      expect { matcher.choose!(workout, chosen) }.to raise_error(described_class::Rejected, "This workout already has a ride. Reload the page and try again.")
    end
  end

  describe "GAR-009 rides found" do
    it "groups unlinked cycling rides by date, newest first" do
      date = Date.new(2026, 9, 16)
      morning = ride(date, hour: 7)
      evening = ride(date, hour: 18)
      next_day = ride(date + 1)
      linked = ride(date + 2)
      Activities::Linker.new(linked).link!(completed(date + 2), origin: :rider)
      ride(date, sport: :yoga, average_power_watts: nil, np_watts: nil, intensity_factor: nil, tss: nil, work_kj: nil)
      ride(date + 5)
      create(:activity, :unlinked, :garmin, started_on: date)

      expect(matcher.found_rides(date..(date + 2))).to eq(date => [ evening, morning ], date + 1 => [ next_day ])
    end
  end
end
