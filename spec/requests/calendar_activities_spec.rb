require "rails_helper"

RSpec.describe "Calendar activities", type: :request do
  let(:rider) { create(:user) }
  let(:plan) { create(:training_plan, user: rider) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }

  before do
    travel_to Date.new(2026, 9, 21)
    sign_in_as(rider)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def day(date)
    get root_path
    page.at_css("#calendar-day-#{date.iso8601}")
  end

  def entries(date)
    day(date).css("[aria-label='Activities'] li").map { |entry| entry.text.squish }
  end

  def activity(on, name, *traits, **attributes)
    create(:activity, :unlinked, :garmin, *traits, user: rider, name: name, started_at: on.in_time_zone.change(hour: 7), started_on: on, **attributes)
  end

  it "GAR-010 lists an unlinked ride under the workout on its day with sport, name, duration and TSS" do
    date = Date.new(2026, 9, 15)
    create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: date, name: "Tempo ride")
    activity(date, "Lunch ride", moving_seconds: 3600, elapsed_seconds: 3700, tss: 58.4)

    expect(day(date).text).to include("Tempo ride")
    expect(entries(date)).to eq([ "Cycling · Lunch ride · 1:00:00 · 58 TSS" ])
  end

  it "GAR-010 lists activities on a rest day in start order, with a ride's moving time, another sport's elapsed time and no TSS without power" do
    date = Date.new(2026, 9, 16)
    phase
    create(
      :activity,
      :unlinked,
      :garmin,
      user: rider,
      sport: :running,
      name: "Evening run",
      started_at: date.in_time_zone.change(hour: 18),
      started_on: date,
      moving_seconds: 1800,
      elapsed_seconds: 1900,
      average_power_watts: nil,
      np_watts: nil,
      intensity_factor: nil,
      tss: nil,
      work_kj: nil)
    activity(date, "Commute", :without_power, moving_seconds: 1500, elapsed_seconds: 1500)

    expect(entries(date)).to eq([ "Cycling · Commute · 0:25:00", "Running · Evening run · 0:31:40" ])
  end

  it "GAR-010 shows a linked ride only as ridden figures on its workout card" do
    date = Date.new(2026, 9, 15)
    workout = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: date, name: "Tempo ride")
    ride = activity(date, "Lunch ride", tss: 58.4)
    Activities::Linker.new(ride).link!(workout, origin: :rider)

    expect(day(date).text).to include("Ridden: 58 TSS")
    expect(day(date).at_css("[aria-label='Activities']")).to be_nil
    expect(response.body).not_to include("Lunch ride")
  end

  it "GAR-010 shows activities only on dates inside the active plan's calendar" do
    phase
    activity(plan.starts_on, "First day")
    activity(plan.ends_on, "Last day")
    activity(plan.starts_on - 1, "Before the plan")
    activity(plan.ends_on + 1, "After the plan")

    get root_path

    expect(response.body).to include("First day", "Last day")
    expect(response.body).not_to include("Before the plan", "After the plan")
  end

  it "GAR-012 never shows another rider's activities" do
    date = Date.new(2026, 9, 16)
    phase
    other = create(:user)
    create(:activity, :unlinked, :garmin, user: other, name: "Someone else's ride", started_at: date.in_time_zone.change(hour: 7), started_on: date)

    get root_path

    expect(response.body).not_to include("Someone else's ride")
  end

  it "GAR-013 keeps weekly totals planned-only" do
    date = Date.new(2026, 9, 15)
    create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: date, name: "Tempo ride")
    activity(date + 1, "Long ride", moving_seconds: 7200, elapsed_seconds: 7200, tss: 140)

    get root_path
    summary = page.at_css("[aria-label='Weekly summary for #{date.beginning_of_week.to_fs(:long)}']").text.squish

    expect(summary).to include("Duration 1 h 00 min", "Load 42 TSS", "Work 608 kJ")
  end
end
