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

  it "PLN-010 renders one configuration form with all plan inputs" do
    get new_training_plan_path
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    form = html.css("form").find { |element| element["action"] == preview_training_plan_path }
    expect(form).to be_present
    expect(form["data-turbo"]).to eq("false")
    expect(response.body).to include("Goal", "Discipline", "Timing", "Target event", "FTP (watts)", "Weekly availability", "Preview plan")
    expect(response.body).to include(
      "Balances aerobic endurance with varied intensity",
      "Prioritises threshold, VO2 Max and over-under progression",
      "Emphasises endurance volume",
      "sustained climbing efforts",
      "shape speciality sessions, taper and opener"
    )
  end

  it "PLN-013 generates and renders an in-memory preview without persisting a plan" do
    expect {
      post preview_training_plan_path, params: { plan_configuration: plan_configuration }
    }.not_to change { [ TrainingPlan.count, PlannedWorkout.count, PlanPhase.count, TargetEvent.count, AvailabilityTemplate.count ] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Plan preview", "Phase timeline", "Weekly template", "FTP assessments", "Projected weekly load", "Back to edit")
    expect(response.body).to include("Recovery week")
  end

  it "PLN-010 returns useful validation errors without generating a preview" do
    post preview_training_plan_path, params: { plan_configuration: plan_configuration(ftp_watts: "", availability: {}) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please correct the plan configuration", "Ftp watts can&#39;t be blank")
  end

  it "PLN-022 displays target-event taper and opener details" do
    post preview_training_plan_path, params: { plan_configuration: plan_configuration(goal: "event", event_name: "Autumn Classic", event_on: "2026-12-06", event_discipline: "road", event_expected_duration_minutes: "360") }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Target event:", "Taper and opener", "Event Opener")
  end

  it "PLN-013 / CAL-001 confirms the preview and renders a continuous persisted calendar" do
    post preview_training_plan_path, params: { plan_configuration: plan_configuration }
    expect {
      post training_plan_path
    }.to change(TrainingPlan, :count).by(1)
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Training calendar", "Training plan created.", "November")
    expect(response.body).to include("FTP Test")
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
      post preview_training_plan_path, params: { plan_configuration: plan_configuration(ftp_watts: "285", event_name: "Private event") }
      expect(response).to have_http_status(:ok)

      switch_to_other_user
      get new_training_plan_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('input[name="plan_configuration[ftp_watts]"]')["value"]).to eq("310")
      expect(html.at_css('input[name="plan_configuration[event_name]"]')["value"]).to be_blank
    end

    it "rejects confirmation of a draft created by another rider" do
      post preview_training_plan_path, params: { plan_configuration: plan_configuration }
      switch_to_other_user

      expect { post training_plan_path }.not_to change(TrainingPlan, :count)
      expect(response).to redirect_to(new_training_plan_path)
      follow_redirect!
      expect(response.body).to include("Preview the plan again before creating it.")
    end

    it "allows the second rider to preview and confirm their own configuration after switching" do
      post preview_training_plan_path, params: { plan_configuration: plan_configuration(ftp_watts: "285") }
      switch_to_other_user
      post preview_training_plan_path, params: { plan_configuration: plan_configuration(ftp_watts: "310") }

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
        post preview_training_plan_path, params: { plan_configuration: inputs }
        back_to_edit
        2.times do
          inputs.except(:availability, :include_base).each { |name, value| expect(field_value(name)).to eq(value) }
          expect(field_value(:include_base)).to be(false)
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
        post preview_training_plan_path, params: { plan_configuration: inputs }
        back_to_edit
      }.not_to change { plan_record_counts }
      inputs.except(:availability, :include_base).each { |name, value| expect(field_value(name)).to eq(value) }
      expect(field_value(:include_base)).to be(true)
    end

    it "confirms revised settings, event and availability after editing and clears the draft" do
      user.create_rider_profile!(ftp_watts: 240)
      get new_training_plan_path
      expect(field_value(:ftp_watts)).to eq("240")
      expect(field_value(:goal)).to eq("general_fitness")
      expect(field_value(:duration_months)).to eq("3")

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
        post preview_training_plan_path, params: { plan_configuration: plan_configuration }
        back_to_edit
        post preview_training_plan_path, params: { plan_configuration: revised }
        expect(response.body).to include("Revised event", "120 min Endurance", "75 min Threshold")
        back_to_edit
        expect(field_value("availability][1][enabled")).to be(false)
        expect(field_value("availability][7][enabled")).to be(true)
        post preview_training_plan_path, params: { plan_configuration: revised }
      }.not_to change { plan_record_counts }

      expect { post training_plan_path }.to change(TrainingPlan, :count).by(1)
      expect(response).to redirect_to(root_path)
      plan = TrainingPlan.active.sole
      expect(plan).to have_attributes(
        goal: "event",
        discipline: "gravel",
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

    it "renders invalid edits and confirms a corrected preview" do
      post preview_training_plan_path, params: { plan_configuration: plan_configuration }
      back_to_edit
      expect {
        post preview_training_plan_path, params: { plan_configuration: plan_configuration(ftp_watts: "0", discipline: "gravel") }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Please correct the plan configuration")
        expect(field_value(:ftp_watts)).to eq("0")
        expect(field_value(:discipline)).to eq("gravel")
        get new_training_plan_path
        expect(field_value(:ftp_watts)).to eq("260")
        post preview_training_plan_path, params: { plan_configuration: plan_configuration(ftp_watts: "290", discipline: "gravel") }
      }.not_to change { plan_record_counts }
      expect { post training_plan_path }.to change(TrainingPlan, :count).by(1)
      expect(TrainingPlan.active.sole).to have_attributes(initial_ftp_watts: 290, discipline: "gravel")
    end
  end
end
