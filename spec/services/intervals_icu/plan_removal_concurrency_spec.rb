require "rails_helper"

RSpec.describe "CYF-79 sync and plan removal", type: :model do
  uses_transaction "finishes an in-flight sync before deleting its events and plan"

  it "finishes an in-flight sync before deleting its events and plan" do
    user = create(:user)
    create(:rider_profile, user: user, intervals_icu_api_key: "test-key")
    plan = create(:training_plan, user: user)
    workout = create(:planned_workout, :structured, training_plan: plan, scheduled_on: Date.current)
    uploaded = Queue.new
    release = Queue.new
    deleting = Queue.new
    events = []
    client = instance_double(IntervalsIcu::Client)
    allow(IntervalsIcu::Client).to receive(:new).and_return(client)
    allow(client).to receive(:upsert_events) do |payloads|
      events.concat(payloads.pluck(:external_id))
      uploaded << true
      release.pop
      payloads.map { |payload| { "id" => 100, "external_id" => payload.fetch(:external_id) } }
    end
    allow(client).to receive(:delete_events) { |ids| events.reject! { |id| ids.include?(id) } }
    syncing = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        IntervalsIcu::SyncNextTwo.new(plan: TrainingPlan.find(plan.id)).call
      end
    end
    uploaded.pop
    # Read through this separate connection while the upload is in flight:
    # process failure must not lose the already committed remote identity.
    expect(IntervalsIcuSync.where(planned_workout: workout)).to exist
    removal = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        remover = Planning::PlanRemover.new(TrainingPlan.find(plan.id))
        deleting << true
        remover.call
      end
    end
    deleting.pop
    release << true
    syncing.value
    removal.value

    expect(events).to be_empty
    expect(TrainingPlan.exists?(plan.id)).to be(false)
    expect(IntervalsIcuSync.where(user: user)).not_to exist
    expect(client).to have_received(:delete_events).with([ "cyclefar-workout-#{workout.id}" ])
  ensure
    release << true if release
    syncing&.join
    removal&.join
    TrainingPlan.find_by(id: plan&.id)&.destroy!
    user&.rider_profile&.destroy!
    user&.reload&.destroy!
  end
end
