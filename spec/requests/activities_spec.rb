require "rails_helper"

RSpec.describe "Activity detail", type: :request do
  let(:rider) { create(:user) }
  let(:plan) { create(:training_plan, user: rider) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:date) { Date.new(2026, 9, 16) }

  before do
    travel_to Date.new(2026, 9, 21)
    sign_in_as(rider)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def figures
    page.css("[aria-label='Activity figures'] div").to_h { |row| [ row.at_css("dt").text.squish, row.at_css("dd").text.squish ] }
  end

  def detail_text
    page.at_css("[aria-labelledby='activity-detail-title']").text.squish
  end

  it "GAR-010 opens a calendar entry in the activity detail frame" do
    phase
    ride = create(:activity, :unlinked, :garmin, user: rider, name: "Lunch ride", started_at: date.in_time_zone.change(hour: 12), started_on: date)

    get root_path
    link = page.css("[aria-label='Activities'] a").sole

    expect(link["href"]).to eq(activity_path(ride))
    expect(page.at_css("turbo-frame#activity_detail")).to be_present
    expect(link["data-turbo-frame"]).to eq("activity_detail")

    get link["href"], headers: { "Turbo-Frame" => "activity_detail" }

    frame = page.at_css("turbo-frame#activity_detail")
    expect(frame.at_css("dialog[aria-labelledby='activity-detail-title']")).to be_present
    expect(frame.css("button").map { |button| button.text.strip }).to include("Close")
  end

  it "GAR-010 shows an unlinked ride's ridden figures at the FTP on the ride date" do
    ride = create(
      :activity,
      :unlinked,
      :garmin,
      user: rider,
      name: "Lunch ride",
      started_at: date.in_time_zone.change(hour: 12),
      started_on: date,
      figures_ftp_watts: 255,
      moving_seconds: 3600,
      elapsed_seconds: 3725,
      average_power_watts: 180.4,
      np_watts: 191.6,
      intensity_factor: 0.75137,
      tss: 56.4,
      work_kj: 649.4,
      average_heart_rate_bpm: 141.3)

    get activity_path(ride)

    expect(response).to have_http_status(:ok)
    expect(page.at_css("#activity-detail-title").text).to eq("Lunch ride")
    expect(detail_text).to include("September 16, 2026", "Cycling", "Garmin Connect")
    expect(detail_text).to include("Figures use your FTP on the ride date: 255 W.")
    expect(figures).to eq(
      "Duration" => "1:00:00 moving · 1:02:05 elapsed",
      "Average power" => "180 W",
      "NP" => "192 W",
      "IF" => "0.75",
      "TSS" => "56",
      "Work" => "649 kJ",
      "Average heart rate" => "141 bpm")
  end

  it "GAR-010 shows a ride without power as duration and heart rate with No power data" do
    ride = create(
      :activity,
      :unlinked,
      :garmin,
      :without_power,
      user: rider,
      name: "Commute",
      started_at: date.in_time_zone.change(hour: 8),
      started_on: date,
      moving_seconds: 1500,
      elapsed_seconds: 1600,
      average_heart_rate_bpm: nil)

    get activity_path(ride)

    expect(figures).to eq(
      "Duration" => "0:25:00 moving · 0:26:40 elapsed",
      "Power" => "No power data",
      "Average heart rate" => "Not recorded")
    expect(detail_text).not_to include("FTP")
  end

  it "GAR-010 shows another sport's duration, distance and heart rate" do
    run = create(
      :activity,
      :unlinked,
      :garmin,
      :without_power,
      user: rider,
      sport: :running,
      external_type: "trail_running",
      name: "Evening run",
      started_at: date.in_time_zone.change(hour: 18),
      started_on: date,
      moving_seconds: 1750,
      elapsed_seconds: 1800,
      distance_metres: 5234.5,
      average_heart_rate_bpm: 152)

    get activity_path(run)

    expect(detail_text).to include("Running", "Garmin Connect")
    expect(figures).to eq(
      "Duration" => "0:30:00",
      "Distance" => "5.23 km",
      "Average heart rate" => "152 bpm")
    expect(detail_text).not_to include("FTP", "TSS")
  end

  it "GAR-010 shows Not recorded for another sport without distance" do
    yoga = create(
      :activity,
      :unlinked,
      :garmin,
      :without_power,
      user: rider,
      sport: :yoga,
      name: nil,
      started_at: date.in_time_zone.change(hour: 18),
      started_on: date,
      moving_seconds: 2700,
      elapsed_seconds: 2700,
      distance_metres: nil,
      average_heart_rate_bpm: nil)

    get activity_path(yoga)

    expect(page.at_css("#activity-detail-title").text).to eq("Yoga")
    expect(figures).to eq("Duration" => "0:45:00", "Distance" => "Not recorded", "Average heart rate" => "Not recorded")
  end

  it "GAR-011 labels an uploaded activity Uploaded FIT, including once merged with Garmin" do
    upload = create(:activity, :unlinked, user: rider, name: nil, started_at: date.in_time_zone.change(hour: 7), started_on: date)
    merged = create(
      :activity,
      :unlinked,
      user: rider,
      name: "Merged ride",
      garmin_activity_id: 25_123_456_789,
      started_at: date.in_time_zone.change(hour: 17),
      started_on: date)

    get activity_path(upload)
    expect(page.at_css("#activity-detail-title").text).to eq("Ride")
    expect(detail_text).to include("Uploaded FIT")
    expect(detail_text).not_to include("Garmin Connect")

    get activity_path(merged)
    expect(detail_text).to include("Uploaded FIT")
    expect(detail_text).not_to include("Garmin Connect")
  end

  it "GAR-010 shows a linked ride with its workout and completion FTP" do
    workout = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: date, name: "Tempo ride")
    ride = create(:activity, :unlinked, :garmin, user: rider, name: "Tempo outside", started_at: date.in_time_zone.change(hour: 7), started_on: date)
    Activities::Linker.new(ride).link!(workout, origin: :rider)
    ride.update!(figures_ftp_watts: 260)

    get activity_path(ride)

    expect(detail_text).to include("Linked to Tempo ride on September 16, 2026.", "Figures use your completion FTP of 260 W.")
    expect(detail_text).not_to include("FTP on the ride date")
    expect(page.css("a").find { |link| link.text == "Tempo ride" }["href"]).to eq(planned_workout_path(workout))
  end

  it "GAR-012 gives another rider's activity the same 404 as a missing one" do
    other = create(:activity, :unlinked, :garmin, user: create(:user), started_at: date.in_time_zone.change(hour: 7), started_on: date)

    get activity_path(other)
    expect(response).to have_http_status(:not_found)

    get activity_path(Activity.maximum(:id) + 1)
    expect(response).to have_http_status(:not_found)
  end

  it "keeps the detail view read-only" do
    ride = create(:activity, :unlinked, :garmin, user: rider, started_at: date.in_time_zone.change(hour: 7), started_on: date)

    get activity_path(ride)

    detail = page.at_css("[aria-labelledby='activity-detail-title']")
    expect(detail.css("form, input, select, textarea")).to be_empty
  end
end
