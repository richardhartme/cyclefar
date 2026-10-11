require "rails_helper"

RSpec.describe "CYF-83 FTP refresh concurrency", type: :model do
  uses_transaction "commits FTP before HTTP and refreshes a queued manual sync with current FTP"
  uses_transaction "serializes two FTP changes without an older upload winning"
  uses_transaction "finishes FTP refresh before plan deletion and never recreates deleted events"

  before do
    @user = create(:user)
    @profile = create(:rider_profile, user: @user, ftp_watts: 260, intervals_icu_api_key: "test-key")
    create(:ftp_reading, rider_profile: @profile, ftp_watts: 260, effective_on: Date.current - 1)
    @plan = create(:training_plan, user: @user)
    @workout = create(:planned_workout, :structured, training_plan: @plan, scheduled_on: Date.current)
    create(:intervals_icu_sync, planned_workout: @workout, intervals_event_id: 100, last_synced_at: 1.day.ago)
    @uploaded = Queue.new
    @release = Queue.new
    @threads = []
    @payloads = []
    @client = instance_double(IntervalsIcu::Client)
    allow(IntervalsIcu::Client).to receive(:new).and_return(@client)
    allow(@client).to receive(:upsert_events) do |events|
      expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
      @payloads << events
      if @payloads.size == 1
        @uploaded << true
        Timeout.timeout(10) { @release.pop }
      end
      events.map { |event| { "id" => 100, "external_id" => event[:external_id] } }
    end
    allow(@client).to receive(:delete_events)
  end

  after do
    @release << true
    @threads.each { |thread| Timeout.timeout(15) { thread.join } }
    TrainingPlan.find_by(id: @plan.id)&.destroy!
    @user.intervals_icu_syncs.destroy_all
    @user.rider_profile.ftp_readings.destroy_all
    @user.rider_profile.destroy!
    @user.reload.destroy!
  end

  def run_in_connection(&block)
    @threads << Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }
    @threads.last
  end

  def change_ftp(watts)
    run_in_connection do
      Settings::Update.new(profile: RiderProfile.find(@profile.id), attributes: { ftp_watts: watts }).call
    end
  end

  def wait_for(queue)
    Timeout.timeout(10) { queue.pop }
  end

  it "commits FTP before HTTP and refreshes a queued manual sync with current FTP" do
    stale_profile = RiderProfile.find(@profile.id)
    updating = change_ftp(300)
    wait_for(@uploaded)
    expect(@profile.reload.ftp_watts).to eq(300)
    expect(@profile.ftp_readings.newest_first.first.ftp_watts).to eq(300)
    expect(@workout.reload.estimated_work_kj).to eq(702)
    ready = Queue.new
    syncing = run_in_connection do
      service = IntervalsIcu::SyncCalendar.new(plan: TrainingPlan.find(@plan.id), profile: stale_profile)
      ready << true
      service.call
    end
    wait_for(ready)
    @release << true
    Timeout.timeout(15) { updating.value; syncing.value }
    expect(@payloads.map { |events| events.pluck(:icu_ftp) }).to eq([ [ 300 ], [ 300 ] ])
  end

  it "serializes two FTP changes without an older upload winning" do
    first = change_ftp(300)
    wait_for(@uploaded)
    second = change_ftp(320)
    @release << true
    Timeout.timeout(15) { first.value; second.value }
    expect(@payloads.map { |events| events.pluck(:icu_ftp) }).to eq([ [ 300 ], [ 320 ] ])
    expect(@profile.reload.ftp_watts).to eq(320)
  end

  it "finishes FTP refresh before plan deletion and never recreates deleted events" do
    updating = change_ftp(300)
    wait_for(@uploaded)
    ready = Queue.new
    deleting = run_in_connection do
      ready << true
      Planning::PlanRemover.new(TrainingPlan.find(@plan.id)).call
    end
    wait_for(ready)
    @release << true
    Timeout.timeout(15) { updating.value; deleting.value }
    expect(@client).to have_received(:delete_events).with([ "cyclefar-workout-#{@workout.id}" ])
    expect(TrainingPlan.exists?(@plan.id)).to be(false)
    expect(IntervalsIcuSync.where(user: @user)).not_to exist
    expect(@payloads.size).to eq(1)
    expect(Settings::Update.new(profile: @profile.reload, attributes: { ftp_watts: 320 }).call.ftp_watts).to eq(320)
    expect(@payloads.size).to eq(1)
  end
end
