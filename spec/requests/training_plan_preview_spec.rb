require "rails_helper"

RSpec.describe "Training plan preview", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as(user) }

  def plan_configuration(overrides = {})
    {
      goal: "increase_ftp", discipline: "road", starts_on: "2026-09-07", duration_mode: "preset", duration_months: "3",
      ftp_watts: "260", include_base: "1", progression_mode: "hard_recovery_cycle", hard_weeks_before_recovery: "3",
      availability: {
        "1" => { weekday: "1", enabled: "1", duration_minutes: "60", intent: "intervals" },
        "3" => { weekday: "3", enabled: "1", duration_minutes: "90", intent: "endurance" },
        "6" => { weekday: "6", enabled: "1", duration_minutes: "60", intent: "intervals" }
      }
    }.merge(overrides)
  end

  def submit_preview(configuration)
    post preview_training_plan_path, params: { plan_configuration: configuration }
    follow_redirect! if response.redirect?
  end

  it "PLN-013 redirects to a refreshable preview without persisting a plan" do
    expect {
      post preview_training_plan_path, params: { plan_configuration: plan_configuration }
      expect(response).to redirect_to(preview_training_plan_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Plan preview")
      get preview_training_plan_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Plan preview")
    }.not_to change { [ TrainingPlan.count, PlannedWorkout.count, PlanPhase.count, TargetEvent.count, AvailabilityTemplate.count ] }
  end

  it "redirects an unowned or missing preview draft to the plan form" do
    get preview_training_plan_path
    expect(response).to redirect_to(new_training_plan_path)
  end

  it "PLN-010 renders one configuration form with all plan inputs" do
    get new_training_plan_path
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    form = html.css("form").find { |element| element["action"] == preview_training_plan_path }
    expect(form).to be_present
    expect(form["data-turbo"]).to eq("false")
    expect(response.body).to include("Goal", "Plan length", "Timing", "Target event", "FTP (watts)", "Weekly availability", "Preview plan")
    expect(response.body).to include("For Intervals days", "Tempo and Sweet Spot", "Threshold and VO2 Max", "over-under", "event discipline")
    expect(response.body).not_to include("Emphasises endurance volume")
  end

  it "CYF-89 / PLN-012 / PLN-020 explains Base, recovery and taper with an accessible dependent cycle field" do
    get new_training_plan_path
    html = Nokogiri::HTML(response.body)
    progression = html.at_xpath("//fieldset[legend[normalize-space()='Fitness and progression']]")
    expect(progression.text).to include("Adds an initial foundation phase before Build and Speciality.")
    expect(progression.text).to include("Continuous progression — no scheduled recovery weeks")
    expect(progression.text).to include("Scheduled recovery weeks and event taper", "shorten normal sessions", "change session types")
    expect(progression.text).to include("time off")
    expect(progression.at_css('[data-plan-configuration-target="phaseSequence"]')["aria-live"]).to eq("polite")
    cycle = progression.at_css('[data-plan-configuration-target="cycle"]')
    expect(cycle.key?("hidden")).to be(true)
    expect(cycle.key?("disabled")).to be(true)
    weeks = cycle.at_css('input[name="plan_configuration[hard_weeks_before_recovery]"]')
    expect(weeks["required"]).to eq("required")
    expect(weeks["step"]).to eq("1")
  end

  it "CYF-89 / PLN-012 ignores a stale count for Continuous mode through confirmation" do
    submit_preview(plan_configuration(progression_mode: "continuous", hard_weeks_before_recovery: "invalid"))
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Continuous progression — no scheduled recovery weeks")
    link = Nokogiri::HTML(response.body).at_xpath("//a[text()='Back to edit']")
    get link["href"]
    expect(Nokogiri::HTML(response.body).at_css('input[name="plan_configuration[hard_weeks_before_recovery]"]')["value"]).to eq("invalid")
    post training_plan_path
    expect(response).to redirect_to(root_path)
    expect(TrainingPlan.active.sole).to have_attributes(progression_mode: "continuous", hard_weeks_before_recovery: nil)
  end

  it "CYF-89 / PLN-012 retains cycle count after validation errors and Back to edit" do
    submit_preview(plan_configuration(hard_weeks_before_recovery: "2.5"))
    expect(response).to have_http_status(:unprocessable_content)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('input[name="plan_configuration[hard_weeks_before_recovery]"]')["value"]).to eq("2.5")
    expect(html.at_css('[data-plan-configuration-target="cycle"]').key?("hidden")).to be(false)
    expect(response.body).to include("Hard weeks before recovery must be a positive whole number")

    submit_preview(plan_configuration(hard_weeks_before_recovery: "4"))
    link = Nokogiri::HTML(response.body).at_xpath("//a[text()='Back to edit']")
    get link["href"]
    expect(Nokogiri::HTML(response.body).at_css('input[name="plan_configuration[hard_weeks_before_recovery]"]')["value"]).to eq("4")
  end

  it "CYF-88 / PLN-011 explains the session choices with weekday-specific accessible names" do
    get new_training_plan_path
    html = Nokogiri::HTML(response.body)
    availability = html.at_xpath("//fieldset[legend[normalize-space()='Weekly availability']]")

    expect(availability).to be_present
    expect(availability.text).to include("Choose your training days and session lengths. Select Intervals to let CycleFar choose the workout type, or select a specific type yourself.")
    expect(availability.text).to include("Endurance and Recovery", "Unselected days are rest days", "does not add training days or available time")
    expect(availability.text).to include("VO2 Max, Threshold, Sweet Spot and Tempo", "recovery weeks and taper")
    expect(availability.css("thead th").map(&:text)).to eq([ "Day", "Train", "Duration", "Session type" ])

    (1..7).each do |weekday|
      day_name = Date::DAYNAMES.rotate.fetch(weekday - 1)
      choice = availability.at_css("select[name='plan_configuration[availability][#{weekday}][intent]']")
      expect(choice["aria-label"]).to eq("#{day_name} session type")
      expect(choice.css("option").map { |option| [ option.text, option["value"] ] }).to include([ "Intervals — chosen for your goal", "intervals" ])
    end
  end

  it "CYF-88 / PLN-011 ignores unchecked-day values but validates selected days" do
    invalid_day = { weekday: "2", duration_minutes: "invalid", intent: "invalid" }
    submit_preview(plan_configuration(availability: plan_configuration[:availability].merge("2" => invalid_day)))
    expect(response).to have_http_status(:ok)

    submit_preview(plan_configuration(availability: plan_configuration[:availability].merge("2" => invalid_day.merge(enabled: "1"))))
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("contains an invalid training day")
  end

  it "PLN-013 generates and renders an in-memory preview without persisting a plan" do
    expect {
      submit_preview(plan_configuration)
    }.not_to change { [ TrainingPlan.count, PlannedWorkout.count, PlanPhase.count, TargetEvent.count, AvailabilityTemplate.count ] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Plan preview", "Phase timeline", "Weekly template", "Projected weekly load", "Back to edit")
    expect(response.body).to include("Recovery week")
    expect(response.body).not_to include("FTP assessments", "FTP Test")
  end

  it "PLN-010 returns useful validation errors without generating a preview" do
    submit_preview(plan_configuration(ftp_watts: "", availability: {}))
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please correct the plan configuration", "Ftp watts can&#39;t be blank")
  end

  it "PLN-022 displays target-event taper and opener details" do
    submit_preview(plan_configuration(goal: "event", event_name: "Autumn Classic", event_on: "2026-12-06", event_discipline: "road", event_expected_duration_minutes: "360"))
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Target event:", "Taper and opener", "Event Opener")
  end

  it "PLN-013 / CAL-001 confirms the preview and renders a continuous persisted calendar" do
    submit_preview(plan_configuration)
    expect {
      post training_plan_path
    }.to change(TrainingPlan, :count).by(1)
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Training calendar", "Training plan created.", "November")
    expect(response.body).not_to include("FTP Test", "FTP assessments", "Test done")
    expect(response.body).to include("Workout power profile")
    expect(Nokogiri::HTML(response.body).css("svg polygon")).not_to be_empty
    expect(TrainingPlan.active.sole.planned_workouts.structured.count).to be < TrainingPlan.active.sole.planned_workouts.count
  end

  describe "USR-005 preview ownership" do
    let(:other_user) { create(:user) }

    def switch_to_other_user
      delete session_path
      expect(response).to redirect_to(new_session_path)
      sign_in_as(other_user)
    end

    it "does not show the first rider's draft when another rider signs in with the same browser" do
      other_user.create_rider_profile!(ftp_watts: 310)
      submit_preview(plan_configuration(ftp_watts: "285", event_name: "Private event"))
      expect(response).to have_http_status(:ok)

      switch_to_other_user
      get preview_training_plan_path
      expect(response).to redirect_to(new_training_plan_path)
      get new_training_plan_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('input[name="plan_configuration[ftp_watts]"]')["value"]).to eq("310")
      expect(html.at_css('input[name="plan_configuration[event_name]"]')["value"]).to be_blank
    end

    it "rejects confirmation of a draft created by another rider" do
      submit_preview(plan_configuration)
      switch_to_other_user

      expect { post training_plan_path }.not_to change(TrainingPlan, :count)
      expect(response).to redirect_to(new_training_plan_path)
      follow_redirect!
      expect(response.body).to include("Preview the plan again before creating it.")
    end

    it "allows the second rider to preview and confirm their own configuration after switching" do
      submit_preview(plan_configuration(ftp_watts: "285"))
      switch_to_other_user
      submit_preview(plan_configuration(ftp_watts: "310"))

      expect { post training_plan_path }.to change(TrainingPlan, :count).by(1)
      expect(TrainingPlan.active.sole).to have_attributes(user: other_user, initial_ftp_watts: 310)
    end
  end

  describe "PLN-013 editing a preview" do
    before { travel_to Time.zone.local(2026, 9, 7, 12) }
    after { travel_back }

    def back_to_edit
      link = Nokogiri::HTML(response.body).at_xpath("//a[text()='Back to edit']")
      expect(link).to be_present
      get link["href"]
      expect(response).to have_http_status(:ok)
    end

    def field_value(name)
      controls = Nokogiri::HTML(response.body).css("[name='plan_configuration[#{name}]']")
      expect(controls).not_to be_empty
      control = controls.find { |node| node["type"] != "hidden" }
      case control["type"]
      when "radio"
        controls.find { |node| node.key?("checked") }&.[]("value")
      when "checkbox"
        control.key?("checked")
      else
        control.name == "select" ? control.at_css("option[selected]")&.[]("value") : control["value"]
      end
    end

    def plan_record_counts
      [ TrainingPlan, PlannedWorkout, WorkoutStep, PlanPhase, TargetEvent, AvailabilityTemplate, AvailabilitySlot ].map(&:count)
    end

    it "restores custom settings and active slots on repeated edit visits without persisting records" do
      inputs = plan_configuration(discipline: "gravel", duration_mode: "custom", custom_duration_weeks: "8", include_base: "0", ftp_watts: "285")
      expect {
        submit_preview(inputs)
        back_to_edit
        2.times do
          inputs.except(:availability, :include_base, :discipline, :duration_mode, :duration_months).each { |name, value| expect(field_value(name)).to eq(value) }
          expect(field_value(:include_base)).to be(false)
          expect(field_value(:plan_length)).to eq("custom")
          (1..7).each do |weekday|
            slot = inputs[:availability][weekday.to_s]
            expect(field_value("availability][#{weekday}][enabled")).to eq(slot.present?)
            next unless slot

            expect(field_value("availability][#{weekday}][duration_minutes")).to eq(slot[:duration_minutes])
            expect(field_value("availability][#{weekday}][intent")).to eq(slot[:intent])
          end
          get new_training_plan_path
        end
      }.not_to change { plan_record_counts }
    end

    it "restores event details and the selected month preset" do
      inputs = plan_configuration(
        goal: "event",
        duration_months: "6",
        event_name: "Gravel Classic",
        event_on: "2026-12-06",
        event_discipline: "gravel",
        event_distance_km: "125.5",
        event_elevation_m: "0",
        event_expected_duration_minutes: "360")
      expect {
        submit_preview(inputs)
        back_to_edit
      }.not_to change { plan_record_counts }
      inputs.except(:availability, :include_base, :discipline, :duration_mode, :duration_months).each { |name, value| expect(field_value(name)).to eq(value) }
      expect(field_value(:include_base)).to be(true)
      expect(field_value(:plan_length)).to eq("6")
    end

    it "confirms revised settings, event and availability after editing and clears the draft" do
      user.create_rider_profile!(ftp_watts: 240)
      get new_training_plan_path
      expect(field_value(:ftp_watts)).to eq("240")
      expect(field_value(:goal)).to eq("general_fitness")
      expect(field_value(:plan_length)).to eq("3")

      revised = plan_configuration(
        goal: "event",
        discipline: "gravel",
        include_base: "0",
        ftp_watts: "280",
        event_name: "Revised event",
        event_on: "2026-11-29",
        event_discipline: "road",
        event_distance_km: "150.5",
        event_elevation_m: "0",
        event_expected_duration_minutes: "420",
        availability: {
          "1" => { weekday: "1", duration_minutes: "60", intent: "intervals" },
          "3" => { weekday: "3", enabled: "1", duration_minutes: "120", intent: "endurance" },
          "7" => { weekday: "7", enabled: "1", duration_minutes: "75", intent: "threshold" }
        })
      expect {
        submit_preview(plan_configuration)
        back_to_edit
        submit_preview(revised)
        expect(response.body).to include("Revised event", "120 min Endurance", "75 min Threshold")
        back_to_edit
        expect(field_value("availability][1][enabled")).to be(false)
        expect(field_value("availability][7][enabled")).to be(true)
        submit_preview(revised)
      }.not_to change { plan_record_counts }

      expect { post training_plan_path }.to change(TrainingPlan, :count).by(1)
      expect(response).to redirect_to(root_path)
      plan = TrainingPlan.active.sole
      expect(plan).to have_attributes(
        goal: "event",
        discipline: "road",
        initial_ftp_watts: 280,
        include_base: false,
        starts_on: Date.new(2026, 9, 7),
        ends_on: Date.new(2026, 11, 29),
        progression_mode: "hard_recovery_cycle",
        hard_weeks_before_recovery: 3)
      expect(plan.target_event).to have_attributes(
        name: "Revised event",
        discipline: "road",
        distance_km: 150.5,
        elevation_m: 0,
        expected_duration_minutes: 420,
        event_on: Date.new(2026, 11, 29))
      expect(plan.availability_templates.sole.availability_slots.order(:weekday).pluck(:weekday, :duration_minutes, :intent)).to eq(
        [
          [ 3, 120, "endurance" ], [ 7, 75, "threshold" ]
        ])
      follow_redirect!
      expect(response.body).to include("Training calendar", "Revised event")
      get new_training_plan_path
      expect(field_value(:goal)).to eq("general_fitness")
      expect(field_value(:ftp_watts)).to eq("240")
      expect(field_value(:include_base)).to be(true)
      expect(field_value(:event_name)).to be_nil.or eq("")
      expect(field_value("availability][7][enabled")).to be(false)
    end

    it "PLN-010 retains event discipline through validation, preview editing and goal switching" do
      inputs = plan_configuration(
        goal: "event",
        discipline: "gravel",
        event_discipline: "mtb",
        event_name: "Trail race",
        event_on: "2026-12-06")
      submit_preview(inputs.merge(ftp_watts: "0"))
      expect(response).to have_http_status(:unprocessable_content)
      expect(Nokogiri::HTML(response.body).css('[name="plan_configuration[discipline]"]')).to be_empty
      expect(field_value(:event_discipline)).to eq("mtb")
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('[data-plan-configuration-target="duration"]').key?("hidden")).to be(true)
      expect(html.at_css('[data-plan-configuration-target="event"]').key?("hidden")).to be(false)
      expect(html.at_css('select[name="plan_configuration[event_discipline]"]')["aria-describedby"]).to eq("event-discipline-help")
      expect(response.body).to include("Shapes the workout mix as your event approaches.")

      submit_preview(inputs)
      summary = Nokogiri::HTML(response.body).at_css('[aria-label="Plan summary"]')
      expect(summary.text).to include("MTB")
      expect(summary.text).not_to include("Gravel")
      back_to_edit
      expect(Nokogiri::HTML(response.body).css('[name="plan_configuration[discipline]"]')).to be_empty
      expect(field_value(:event_discipline)).to eq("mtb")

      submit_preview(inputs.merge(goal: "increase_ftp"))
      back_to_edit
      expect(Nokogiri::HTML(response.body).css('[name="plan_configuration[discipline]"]')).to be_empty
      expect(field_value(:event_discipline)).to eq("mtb")
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('[data-plan-configuration-target="duration"]').key?("hidden")).to be(false)
      expect(html.at_css('[data-plan-configuration-target="event"]').key?("hidden")).to be(true)

      submit_preview(inputs)
      post training_plan_path
      plan = TrainingPlan.active.sole
      expect(plan.discipline).to eq("mtb")
      expect(plan.target_event.discipline).to eq("mtb")
    end

    it "CYF-85 previews and confirms an event configuration without a separate plan discipline" do
      submit_preview(
        plan_configuration(
          goal: "event",
          event_discipline: "mtb",
          event_name: "Trail race",
          event_on: "2026-12-06").except(:discipline))
      expect(response).to have_http_status(:ok)
      expect { post training_plan_path }.to change(TrainingPlan, :count).by(1)
      expect(TrainingPlan.active.sole.discipline).to eq("mtb")
      expect(TrainingPlan.active.sole.target_event.discipline).to eq("mtb")
    end

    it "renders invalid edits and confirms a corrected preview" do
      submit_preview(plan_configuration)
      back_to_edit
      expect {
        submit_preview(plan_configuration(ftp_watts: "0", discipline: "gravel"))
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Please correct the plan configuration")
        expect(field_value(:ftp_watts)).to eq("0")
        expect(Nokogiri::HTML(response.body).css('[name="plan_configuration[discipline]"]')).to be_empty
        get new_training_plan_path
        expect(field_value(:ftp_watts)).to eq("260")
        submit_preview(plan_configuration(ftp_watts: "290", discipline: "gravel"))
      }.not_to change { plan_record_counts }
      expect { post training_plan_path }.to change(TrainingPlan, :count).by(1)
      expect(TrainingPlan.active.sole).to have_attributes(initial_ftp_watts: 290, discipline: "road")
    end
  end
end
