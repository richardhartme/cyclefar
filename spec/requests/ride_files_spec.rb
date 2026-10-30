require "rails_helper"

RSpec.describe "Ride files", type: :request do
  let(:user) { create(:user) }
  let(:plan) { create(:training_plan, user: user, starts_on: Date.current - 14, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 2, name: "Tempo ride") }

  before { sign_in_as(user) }

  def upload(name)
    Rack::Test::UploadedFile.new(file_fixture("fit/#{name}.fit"), "application/octet-stream", true)
  end

  def ride_table
    Nokogiri::HTML(response.body).at_css('table[aria-label="Planned and ridden metrics"]')
  end

  def row(label)
    ride_table.css("tr").find { |tr| tr.at_css("th")&.text == label }&.css("td")&.map(&:text)
  end

  it "FBK-004 uploads a FIT file to a completed workout and compares planned with ridden metrics" do
    get planned_workout_path(workout)
    expect(response.body).to include("Upload ride file")
    expect(ride_table).to be_nil

    post planned_workout_ride_file_path(workout), params: { ride_file: upload("outdoor_ride") }

    expect(response).to redirect_to(planned_workout_path(workout))
    expect(flash[:notice]).to eq("Ride file added. It was ridden on #{Date.new(2026, 8, 25).to_fs(:long)}, not the scheduled date.")
    follow_redirect!
    expect(response.body).to include("outdoor_ride.fit", "Calculated at your completion FTP of 260 W.", "but the workout was scheduled for")
    expect(row("TSS")).to eq([ "42", "62" ])
    expect(row("NP")).to eq([ "169 W", "227 W" ])
    expect(row("Duration")).to eq([ "1:00:00", "0:46:57 moving · 0:48:54 elapsed" ])
    expect(row("Average heart rate")).to eq([ "—", "142 bpm" ])

    get root_path
    card = Nokogiri::HTML(response.body).css("article").find { |article| article.text.include?("Tempo ride") }
    expect(card.text).to include("Ridden: 62 TSS")
  end

  it "FBK-004 replaces and removes a ride file without changing completed history" do
    before = workout.reload.attributes
    post planned_workout_ride_file_path(workout), params: { ride_file: upload("outdoor_ride") }

    post planned_workout_ride_file_path(workout), params: { ride_file: upload("outdoor_ride_without_power") }
    follow_redirect!
    expect(response.body).to include("Replace ride file", "Remove ride file")
    expect(row("TSS")).to eq([ "42", "No power data" ])

    get root_path
    expect(response.body).not_to include("Ridden:")

    delete planned_workout_ride_file_path(workout)
    expect(response).to have_http_status(:see_other)
    expect(flash[:notice]).to eq("Ride file removed.")
    expect(workout.reload.workout_activity).to be_nil
    expect(workout.attributes).to eq(before)
  end

  it "FBK-004 rejects files that are not FIT activities" do
    text = Rack::Test::UploadedFile.new(StringIO.new("not a ride"), "text/plain", original_filename: "ride.fit")

    post planned_workout_ride_file_path(workout), params: { ride_file: text }

    expect(response).to redirect_to(planned_workout_path(workout))
    expect(flash[:alert]).to eq("Not a FIT file")
    expect(WorkoutActivity.count).to eq(0)
  end

  it "FBK-004 offers ride files only on completed workouts" do
    planned = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1)

    get planned_workout_path(planned)
    expect(response.body).not_to include("Upload ride file")

    post planned_workout_ride_file_path(planned), params: { ride_file: upload("outdoor_ride") }
    expect(flash[:alert]).to eq("Only completed workouts accept ride files")
    expect(WorkoutActivity.count).to eq(0)
  end

  it "FBK-004 keeps ride files to the rider's active plan" do
    other_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    other_phase = create(:plan_phase, training_plan: other_plan, ends_on: other_plan.ends_on)
    other_workout = create(:planned_workout, :completed, training_plan: other_plan, plan_phase: other_phase, scheduled_on: workout.scheduled_on)
    archived = create(:training_plan, :archived, user: user, starts_on: plan.starts_on - 100, ends_on: plan.starts_on - 30)
    archived_phase = create(:plan_phase, training_plan: archived, starts_on: archived.starts_on, ends_on: archived.ends_on)
    archived_workout = create(:planned_workout, :completed, training_plan: archived, plan_phase: archived_phase, scheduled_on: archived.starts_on + 1)
    workout

    [ other_workout, archived_workout ].each do |target|
      post planned_workout_ride_file_path(target), params: { ride_file: upload("outdoor_ride") }
      expect(response).to have_http_status(:not_found)
      delete planned_workout_ride_file_path(target)
      expect(response).to have_http_status(:not_found)
    end
    expect(WorkoutActivity.count).to eq(0)
  end
end
