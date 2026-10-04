require "rails_helper"

RSpec.describe "Calendar card details", type: :request, generated_workouts: true do
  let(:user) { create(:user) }
  let(:profile) { create(:rider_profile, user: user) }
  let(:plan) { create(:training_plan, user: user) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }

  before do
    travel_to Date.new(2026, 9, 7)
    profile
    sign_in_as(user)
  end

  it "CAL-002 shows canonical main-set repetitions, work targets, type and metrics" do
    workout = generated_workout(plan: plan, phase: phase, date: plan.starts_on + 1, level: 2)

    get root_path

    card = workout_card(workout)
    main_set = card.at_css('dl[aria-label="Main set"]')
    expect(main_set.css("dt").map(&:text)).to eq([ "Threshold · 3 × 8 min" ])
    expect(main_set.css("dd").map(&:text)).to eq([ "247–265 W" ])
    expect(card.text).to include(
      "Threshold · 60 min",
      "#{workout.estimated_tss.round} TSS",
      "IF #{format('%.2f', workout.estimated_if)}",
      "#{workout.estimated_work_kj.round} kJ")
    expect(card.at_css('svg[role="img"]')["aria-label"]).to include("Workout power profile")
  end

  it "CAL-002 distinguishes under/over work ranges from warm-up and recovery targets" do
    phase
    workout = Workouts::Creator.new(plan).create!(scheduled_on: plan.starts_on + 1, subtype: :over_under, duration_minutes: 60)

    get root_path

    main_set = workout_card(workout).at_css('dl[aria-label="Main set"]')
    expect(main_set.css("dt").map(&:text)).to eq([ "Under · 6 × 2 min", "Over · 6 × 1 min" ])
    expect(main_set.css("dd").map(&:text)).to eq([ "229–244 W", "265–281 W" ])
    expect(main_set.text).not_to include("Warm", "Recovery", "Easy")
  end

  it "CAL-002 shows both ramp endpoints for undulating endurance" do
    workout = generated_workout(
      plan: plan,
      phase: phase,
      date: plan.starts_on + 1,
      subtype: :endurance,
      variation: "undulating",
      duration: 60)

    get root_path

    main_set = workout_card(workout).at_css('dl[aria-label="Main set"]')
    expect(main_set.text).to include(
      "Rising endurance",
      "Falling endurance",
      "166–177 → 182–192 W",
      "182–192 → 166–177 W")
    # Non-uniform segment durations must remain separate in the summary.
    summaries = [
      "Rising endurance · 3 × 6 min", "Falling endurance · 3 × 6 min",
      "Rising endurance · 5 min 30 sec", "Falling endurance · 5 min 30 sec"
    ]
    expect(main_set.css("dt").map(&:text)).to eq(summaries)
  end

  it "CAL-002 shows opener activation efforts including sub-minute durations" do
    phase
    workout = Workouts::Creator.new(plan).create!(scheduled_on: plan.starts_on + 1, subtype: "opener", duration_minutes: 30)

    get root_path

    card = workout_card(workout)
    expect(card.text).to include("Opener · 30 min")
    main_set = card.at_css('dl[aria-label="Main set"]')
    expect(main_set.css("dt").map(&:text)).to eq([ "Threshold activation · 3 × 1 min", "VO2 activation · 3 × 30 sec" ])
    expect(main_set.css("dd").map(&:text)).to eq([ "260–281 W", "281–307 W" ])
  end

  it "CAL-002 shows outline purpose and phase without detailed targets, graphs or metrics" do
    workout = create(
      :planned_workout,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: plan.starts_on + 14,
      name: "Endurance",
      purpose: "Develops steady aerobic endurance.",
      estimated_tss: 42.25,
      estimated_if: 0.65,
      estimated_work_kj: 608.4)

    get root_path

    card = workout_card(workout)
    expect(card.text).to include("Endurance", "60 min · Base", "Develops steady aerobic endurance.")
    expect(card.css('svg, dl[aria-label="Main set"]')).to be_empty
    expect(card.text).not_to include(" W", "TSS", "IF", "kJ")
    expect(workout.reload).to be_outline
    expect(workout.workout_steps).to be_empty
  end

  it "CAL-002 updates planned targets and work after FTP changes while completed ramp history stays frozen" do
    completed = generated_workout(
      plan: plan,
      phase: phase,
      date: plan.starts_on,
      subtype: :recovery,
      variation: "gentle_ramp")
    Adaptations::CompletionRecorder.new(workout: completed, rpe: 2, completion_quality: "as_planned").call
    planned = generated_workout(plan: plan, phase: phase, date: plan.starts_on + 1, level: 2)
    snapshot = completed.reload.attributes
    steps = completed.workout_steps.map(&:attributes)

    get root_path
    historical_card = workout_card(completed).text
    expect(historical_card).to include("117–130 → 130–143 W", "Completed")
    old_work = planned.estimated_work_kj.round

    Settings::Update.new(profile: profile, attributes: { ftp_watts: 300 }).call
    get root_path

    expect(workout_card(planned).text).to include("285–306 W", "#{planned.reload.estimated_work_kj.round} kJ")
    expect(planned.estimated_work_kj.round).to be > old_work
    expect(workout_card(completed).text).to eq(historical_card)
    expect(completed.reload.attributes).to eq(snapshot)
    expect(completed.workout_steps.map(&:attributes)).to eq(steps)
  end

  it "FTP-001 keeps protocol-free assessment cards free of invented metrics and targets" do
    workout = create(:planned_workout, :ftp_test, training_plan: plan, plan_phase: phase)

    get root_path

    card = workout_card(workout)
    expect(card.text).to include("FTP Test", "Use your preferred assessment")
    expect(card.css('svg, dl[aria-label="Main set"]')).to be_empty
    expect(card.text).not_to include("TSS", "IF", "kJ", " W")
  end

  it "PLN-022 shows supplied event fields in kilometres, metres and minutes" do
    event_plan = create(:training_plan, :event, user: user)
    create(:target_event, training_plan: event_plan, distance_km: 123.45, elevation_m: 2450, expected_duration_minutes: 315)

    get root_path

    card = event_card
    expect(card.text).to include("Autumn sportive", "Target event · Road")
    expect(card.css("dt").map(&:text)).to eq([ "Distance", "Elevation", "Expected duration" ])
    expect(card.css("dd").map(&:text)).to eq([ "123.45 km", "2,450 m", "315 min" ])
  end

  it "PLN-022 omits absent event fields and still displays zero elevation" do
    event_plan = create(:training_plan, :event, user: user)
    create(:target_event, training_plan: event_plan, elevation_m: 0)

    get root_path

    expect(event_card.css("dt").map(&:text)).to eq([ "Elevation" ])
    expect(event_card.css("dd").map(&:text)).to eq([ "0 m" ])
    expect(event_card.text).not_to include("Distance", "Expected duration")
  end

  it "PLN-022 adds no empty detail rows when every optional event field is absent" do
    event_plan = create(:training_plan, :event, user: user)
    create(:target_event, training_plan: event_plan)

    get root_path

    expect(event_card.text).to include("Autumn sportive", "Target event · Road")
    expect(event_card.css("dl")).to be_empty
  end

  def workout_card(workout)
    Nokogiri::HTML(response.body).at_css("a[href='#{planned_workout_path(workout)}']").ancestors("article").first
  end

  def event_card
    Nokogiri::HTML(response.body).css("article").find { |article| article.text.include?("Target event") }
  end
end
