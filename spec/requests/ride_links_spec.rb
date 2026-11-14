require "rails_helper"

RSpec.describe "Ride links", type: :request do
  let(:rider) { create(:user, email_address: "garmin@example.com") }
  let(:plan) { create(:training_plan, user: rider, starts_on: Date.current - 14, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }

  around { |example| with_garmin_rider_email("garmin@example.com") { example.run } }
  before { sign_in_as(rider) }

  def completed(on, name)
    create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: on, name: name)
  end

  def planned(on, name)
    create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: on, name: name)
  end

  def ride(on, name, hour: 7, user: rider)
    create(:activity, :unlinked, :garmin, user: user, name: name, started_at: on.in_time_zone.change(hour: hour), started_on: on)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def card(name)
    get root_path
    page.css("article").find { |article| article.text.include?(name) }
  end

  it "GAR-007 links the one ride on the date when the rider completes the workout" do
    workout = planned(Date.current - 1, "Tempo ride")
    found = ride(Date.current - 1, "Morning ride")

    post complete_planned_workout_path(workout), params: { rpe: 6, completion_quality: "as_planned" }

    expect(flash[:notice]).to eq("Workout completed. Ride linked.")
    expect(found.reload).to have_attributes(planned_workout: workout, link_origin: "automatic")

    get planned_workout_path(workout)
    section = page.at_css("section[aria-labelledby='ride-file-title']")
    expect(section.text).to include("Morning ride", "Garmin Connect")
    expect(section.css("a, button").map { |control| control.text.strip }).to include("Change ride", "Unlink ride")
    expect(section.at_css("input[type=file]")).to be_nil
  end

  it "GAR-008 offers Choose ride on a completed card and relinks a ride from another workout after confirmation" do
    workout = completed(Date.current - 2, "Tempo ride")
    elsewhere = completed(Date.current - 3, "Long ride")
    moving = ride(Date.current - 3, "Saturday ride")
    Activities::Linker.new(moving).link!(elsewhere, origin: :automatic)
    unlinked = ride(Date.current - 1, "Spin")

    choose = card("Tempo ride").css("a").find { |link| link.text == "Choose ride" }
    expect(choose["href"]).to eq(new_planned_workout_ride_link_path(workout))

    get choose["href"]
    options = page.css("[aria-label='Rides to choose from'] li")
    expect(options.map { |option| option.at_css("strong").text }).to eq([ "Spin", "Saturday ride" ])
    expect(options.last.text).to include("Linked to Long ride on #{elsewhere.scheduled_on.to_fs(:long)}")
    expect(options.first.at_css("form")["data-turbo-confirm"]).to be_nil
    expect(options.last.at_css("form")["data-turbo-confirm"]).to eq("Move this ride from Long ride? That workout will be left without a ride.")

    post planned_workout_ride_link_path(workout), params: { activity_id: moving.id }

    expect(response).to redirect_to(planned_workout_path(workout))
    expect(flash[:notice]).to eq("Ride linked.")
    expect(moving.reload).to have_attributes(planned_workout: workout, link_origin: "rider")
    expect(elsewhere.reload.activity).to be_nil
    expect(unlinked.reload.planned_workout).to be_nil
  end

  it "GAR-008 says when no rides are near the workout" do
    workout = completed(Date.current - 2, "Tempo ride")

    get new_planned_workout_ride_link_path(workout)

    expect(response.body).to include("No rides within 3 days of this workout.")
  end

  it "GAR-008 unlinks a Garmin ride and keeps it as an unlinked activity" do
    workout = completed(Date.current - 2, "Tempo ride")
    linked = ride(Date.current - 2, "Morning ride")
    Activities::Linker.new(linked).link!(workout, origin: :automatic)

    delete planned_workout_ride_file_path(workout)

    expect(flash[:notice]).to eq("Ride unlinked. It stays with your activities.")
    expect(linked.reload).to have_attributes(planned_workout: nil, link_origin: nil)
    expect(card("Tempo ride").text).to include("Choose ride")
  end

  it "GAR-011 labels an uploaded ride Uploaded FIT and keeps Upload for it" do
    workout = completed(Date.current - 2, "Tempo ride")
    post planned_workout_ride_file_path(workout), params: { ride_file: Rack::Test::UploadedFile.new(file_fixture("fit/outdoor_ride.fit"), "application/octet-stream", true) }

    get planned_workout_path(workout)
    section = page.at_css("section[aria-labelledby='ride-file-title']")
    expect(section.text).to include("Uploaded FIT")
    expect(section.at_css("input[type=submit]")["value"]).to eq("Replace ride file")
    expect(section.css("button").map { |button| button.text.strip }).to include("Remove ride file")
    expect(section.text).not_to include("Change ride")
  end

  it "GAR-009 prompts Ride found on a planned card and links the preselected ride on completion" do
    workout = planned(Date.current - 1, "Tempo ride")
    ride(Date.current - 1, "Morning ride", hour: 7)
    evening = ride(Date.current - 1, "Evening ride", hour: 18)

    prompt = card("Tempo ride").css("a").find { |link| link.text == "Ride found — mark this workout completed?" }
    expect(prompt["href"]).to eq(planned_workout_path(workout, ride: evening.id, anchor: "mark-completed"))

    get prompt["href"]
    form = page.at_css("form[action='#{complete_planned_workout_path(workout)}']")
    expect(form.text).to include("Links Evening ride")
    expect(form.at_css("input[name=activity_id]")["value"]).to eq(evening.id.to_s)
    expect(workout.reload).to be_planned

    post complete_planned_workout_path(workout), params: { rpe: 6, completion_quality: "as_planned", activity_id: evening.id }

    expect(workout.reload).to be_completed
    expect(evening.reload).to have_attributes(planned_workout: workout, link_origin: "rider")
  end

  it "GAR-008 and GAR-009 hide Choose ride and Ride found from riders without Garmin" do
    with_garmin_rider_email(nil) do
      completed(Date.current - 2, "Tempo ride")
      planned(Date.current - 1, "Spin session")
      ride(Date.current - 1, "Morning ride")

      get root_path

      expect(response.body).not_to include("Choose ride", "Ride found")
      get new_planned_workout_ride_link_path(rider.planned_workouts.find_by!(name: "Tempo ride"))
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GAR-012 owner scoping" do
    it "gives another rider's ride or workout the same 404 as a missing one" do
      workout = completed(Date.current - 2, "Tempo ride")
      someone_elses = ride(Date.current - 2, "Their ride", user: create(:user))
      their_plan = create(:training_plan, user: someone_elses.user, starts_on: plan.starts_on, ends_on: plan.ends_on)
      their_workout = create(:planned_workout, :completed, training_plan: their_plan, scheduled_on: workout.scheduled_on)

      post planned_workout_ride_link_path(workout), params: { activity_id: someone_elses.id }
      expect(response).to have_http_status(:not_found)
      post planned_workout_ride_link_path(workout), params: { activity_id: 0 }
      expect(response).to have_http_status(:not_found)
      get new_planned_workout_ride_link_path(their_workout)
      expect(response).to have_http_status(:not_found)

      fresh = planned(Date.current - 1, "Spin session")
      post complete_planned_workout_path(fresh), params: { rpe: 6, completion_quality: "as_planned", activity_id: someone_elses.id }
      expect(response).to have_http_status(:not_found)
      expect(fresh.reload).to be_planned
      expect(someone_elses.reload.planned_workout).to be_nil
    end
  end

  it "GAR-008 explains a ride that can't be chosen" do
    workout = completed(Date.current - 2, "Tempo ride")
    far = ride(Date.current - 10, "Old ride")

    post planned_workout_ride_link_path(workout), params: { activity_id: far.id }

    expect(response).to redirect_to(new_planned_workout_ride_link_path(workout))
    expect(flash[:alert]).to eq("Choose a ride within 3 days of this workout.")
  end
end
