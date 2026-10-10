require "rails_helper"

RSpec.describe "Plan removal", type: :request do
  let(:user) { create(:user) }
  let(:plan) { create(:training_plan, user: user) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan) }
  let(:sync) { create(:intervals_icu_sync, planned_workout: workout) }
  let(:requests) { [] }
  let(:connection) { double("HTTP connection") }

  before do
    sign_in_as(user)
    allow(Net::HTTP).to receive(:new).and_return(connection)
    allow(connection).to receive(:use_ssl=)
    allow(connection).to receive(:open_timeout=)
    allow(connection).to receive(:read_timeout=)
    allow(connection).to receive(:request) do |request|
      requests << request
      Struct.new(:code, :body).new("200", '{"eventsDeleted":0}')
    end
  end

  def add_key
    create(:rider_profile, user: user, intervals_icu_api_key: "test-key")
  end

  it "CYF-79 deletes owned plan events and detached identities before removing the plan" do
    add_key
    sync
    detached = create(:intervals_icu_sync, user: user, planned_workout: nil, external_id: "cyclefar-deleted-workout")
    foreign = create(:intervals_icu_sync)
    foreign_detached = create(:intervals_icu_sync, user: foreign.user, planned_workout: nil, external_id: "cyclefar-other-deleted")
    archive = create(:training_plan, :archived, user: user)
    archived_sync = create(:intervals_icu_sync, planned_workout: create(:planned_workout, training_plan: archive))

    delete training_plan_path

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("Training plan deleted.")
    expect(TrainingPlan.exists?(plan.id)).to be(false)
    expect(PlannedWorkout.exists?(workout.id)).to be(false)
    expect(IntervalsIcuSync.where(id: [ sync.id, detached.id ])).not_to exist
    expect(IntervalsIcuSync.where(id: [ foreign.id, foreign_detached.id, archived_sync.id ]).count).to eq(3)
    request = requests.sole
    expect(request.method).to eq("PUT")
    expect(request.path).to eq("/api/v1/athlete/0/events/bulk-delete")
    expect(JSON.parse(request.body).pluck("external_id")).to match_array([ sync.external_id, detached.external_id ])
    expect(Base64.strict_decode64(request["Authorization"].delete_prefix("Basic "))).to eq("API_KEY:test-key")
  end

  it "archives completed history unchanged while removing all of the plan's tracked calendar events" do
    add_key
    sync
    completed = create(:planned_workout, :completed, training_plan: plan, scheduled_on: workout.scheduled_on + 1)
    completed_sync = create(:intervals_icu_sync, planned_workout: completed)
    history = completed.attributes
    steps = completed.workout_steps.map(&:attributes)
    feedback = completed.workout_feedback.attributes

    delete training_plan_path

    expect(plan.reload).to be_archived
    expect(PlannedWorkout.exists?(workout.id)).to be(false)
    expect(completed.reload.attributes).to eq(history)
    expect(completed.workout_steps.reload.map(&:attributes)).to eq(steps)
    expect(completed.workout_feedback.reload.attributes).to eq(feedback)
    expect(JSON.parse(requests.sole.body).pluck("external_id")).to match_array([ sync.external_id, completed_sync.external_id ])
    expect(IntervalsIcuSync.where(user: user)).not_to exist
  end

  it "deletes an unsynced plan without a profile or HTTP request" do
    workout
    delete training_plan_path
    expect(TrainingPlan.exists?(plan.id)).to be(false)
    expect(requests).to be_empty
  end

  it "keeps the plan and sync identities when the API key is absent" do
    sync
    delete training_plan_path
    expect(plan.reload).to be_active
    expect(workout.reload).to be_planned
    expect(sync.reload).to be_present
    expect(flash[:alert]).to include("Add an Intervals.icu API key", "retry", "plan has been kept")
    expect(requests).to be_empty
  end

  [ 401, 403, 422, 503 ].each do |status|
    it "preserves the plan after HTTP #{status} and permits a safe retry" do
      add_key
      sync
      allow(connection).to receive(:request).and_return(Struct.new(:code, :body).new(status.to_s, "private upstream error"))

      delete training_plan_path

      expect(plan.reload).to be_active
      expect(workout.reload).to be_planned
      expect(sync.reload).to be_present
      expect(flash[:alert]).to include("cleanup failed", "retry")
      expect(flash[:alert]).not_to include("private upstream error", "test-key")

      allow(connection).to receive(:request).and_return(Struct.new(:code, :body).new("200", '{"eventsDeleted":0}'))
      delete training_plan_path
      expect(TrainingPlan.exists?(plan.id)).to be(false)
      expect(IntervalsIcuSync.exists?(sync.id)).to be(false)
    end
  end

  it "retains uncertain identities and the active plan after a timeout" do
    add_key
    sync
    allow(connection).to receive(:request).and_raise(Net::ReadTimeout)
    delete training_plan_path
    expect(connection).to have_received(:request).twice
    expect(plan.reload).to be_active
    expect(sync.reload.last_synced_at).to be_nil
    expect(flash[:alert]).to include("cleanup failed")
  end

  it "rolls back local cleanup if plan destruction fails after remote success" do
    add_key
    sync
    allow(plan).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)

    expect { Planning::PlanRemover.new(plan).call }.to raise_error(ActiveRecord::RecordNotDestroyed)

    expect(plan.reload).to be_active
    expect(workout.reload).to be_planned
    expect(sync.reload).to be_present
    expect(requests.size).to eq(1)
  end
end
