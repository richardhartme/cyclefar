require "rails_helper"

RSpec.describe "PLN-010 goal-relevant plan timing", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as(user) }

  def inputs(**overrides)
    { goal: "increase_ftp", starts_on: "2028-01-31", plan_length: "1", ftp_watts: "260", include_base: "1",
      availability: { "2" => { weekday: "2", enabled: "1", duration_minutes: "60", intent: "intervals" } } }.merge(overrides)
  end

  def preview(attributes)
    post preview_training_plan_path, params: { plan_configuration: attributes }
    follow_redirect! if response.redirect?
  end

  def html = Nokogiri::HTML(response.body)
  def field(name) = html.at_css("[name='plan_configuration[#{name}]']")
  def section(name) = html.at_css("[data-plan-configuration-target='#{name}']")

  it "starts with one length selector, no non-event discipline, and inactive event/custom controls" do
    get new_training_plan_path
    expect(field(:plan_length).css("option").map(&:text)).to eq([ "1 month", "3 months", "6 months", "Custom weeks" ])
    expect(field(:discipline)).to be_nil
    expect(field(:duration_mode)).to be_nil
    expect(field(:duration_months)).to be_nil
    expect(field(:event_discipline).at_css("option[selected]")["value"]).to eq("road")
    expect(section(:duration).key?("hidden")).to be(false)
    %i[event custom].each do |name|
      expect(section(name).key?("hidden")).to be(true)
      expect(section(name).key?("disabled")).to be(true)
    end
    expect(response.body).to include("Minimum four whole weeks.", "At least four weeks (28 days)")
  end

  it "uses server month-end and whole-week dates in the live summary without persisting anything" do
    expect {
      { "1" => "2028-02-28", "3" => "2028-04-29", "6" => "2028-07-30", "custom" => "2028-02-27" }.each do |length, finish|
        get end_date_training_plan_path, params: { starts_on: "2028-01-31", plan_length: length, custom_duration_weeks: "4" }
        expect(response.parsed_body["ends_on"]).to eq(finish)
      end
      get end_date_training_plan_path, params: { starts_on: "invalid", plan_length: "1" }
      expect(response.parsed_body["ends_on"]).to be_nil
      get end_date_training_plan_path, params: { starts_on: "2028-01-31", plan_length: "custom", custom_duration_weeks: "3" }
      expect(response.parsed_body["ends_on"]).to be_nil
    }.not_to change(TrainingPlan, :count)
  end

  it "PLN-013 ignores inactive invalid event data and confirms the selected month date and internal discipline" do
    preview(
      inputs(
        discipline: "invalid",
        event_discipline: "invalid",
        event_on: "invalid",
        event_name: "Hidden event",
        event_distance_km: "-1",
        event_elevation_m: "-1",
        event_expected_duration_minutes: "bad",
        custom_duration_weeks: "2.5"))
    expect(response).to have_http_status(:ok)
    summary = html.at_css('[aria-label="Plan summary"]')
    expect(summary.text).to include("January 31, 2028", "February 28, 2028")
    expect(summary.text).not_to include("Discipline", "Road", "Hidden event")
    post training_plan_path
    expect(response).to redirect_to(root_path)
    expect(user.training_plans.active.sole).to have_attributes(ends_on: Date.new(2028, 2, 28), discipline: "road")
    expect(user.training_plans.active.sole.target_event).to be_nil
    follow_redirect!
    expect(html.at_css("header").text).not_to include("Road")
  end

  it "PLN-013 previews and confirms event-only dates despite absent or invalid inactive duration" do
    preview(
      inputs(
        goal: "event",
        plan_length: "custom",
        custom_duration_weeks: "-1",
        duration_mode: "invalid",
        duration_months: "bad",
        event_name: "Trail ride",
        event_on: "2028-04-30",
        event_discipline: "mtb",
        event_expected_duration_minutes: "360"))
    expect(response).to have_http_status(:ok)
    expect(html.at_css('[aria-label="Plan summary"]').text).to include("MTB", "April 30, 2028")
    get new_training_plan_path
    expect(section(:duration).key?("hidden")).to be(true)
    expect(section(:duration).key?("disabled")).to be(true)
    expect(section(:event).key?("hidden")).to be(false)
    expect(response.body).to include("Your plan runs from your start date to your event date.")
    expect(field(:custom_duration_weeks)["value"]).to eq("-1")
    post training_plan_path
    plan = user.training_plans.active.sole
    expect(plan).to have_attributes(ends_on: Date.new(2028, 4, 30), discipline: "mtb")
    taper = plan.plan_phases.find_by!(kind: "taper")
    expect((taper.ends_on - taper.starts_on).to_i + 1).to eq(14)
  end

  it "restores custom/disclosure values after errors and Back to edit with accessible inline errors" do
    preview(inputs(plan_length: "custom", custom_duration_weeks: "2.5", event_details_open: "1", event_name: "Saved event"))
    expect(response).to have_http_status(:unprocessable_content)
    expect(field(:custom_duration_weeks)["value"]).to eq("2.5")
    expect(field(:custom_duration_weeks)["aria-invalid"]).to eq("true")
    expect(field(:custom_duration_weeks)["aria-describedby"]).to include("custom_duration_weeks-errors")
    expect(section(:custom).key?("hidden")).to be(false)
    expect(section(:optionalDetails).key?("open")).to be(true)
    expect(html.at_css('[role="alert"]').text).to include("at least 4 whole weeks")
    preview(inputs(plan_length: "custom", custom_duration_weeks: "4", event_details_open: "1", event_name: "Saved event"))
    get new_training_plan_path
    expect(field(:custom_duration_weeks)["value"]).to eq("4")
    expect(field(:event_name)["value"]).to eq("Saved event")
    expect(section(:optionalDetails).key?("open")).to be(true)
    expect(section(:custom).key?("hidden")).to be(false)
    expect(section(:endDate).text).to include("February 27, 2028")
  end

  it "opens optional active errors, retains entered values, and associates event-date errors with their field" do
    preview(
      inputs(
        goal: "event",
        event_name: "Trail ride",
        event_on: "2028-02-27",
        event_discipline: "mtb",
        event_distance_km: "-10",
        event_expected_duration_minutes: "1.5",
        event_details_open: "0"))
    expect(response).to have_http_status(:unprocessable_content)
    expect(section(:optionalDetails).key?("open")).to be(true)
    expect(field(:event_distance_km)["value"]).to eq("-10")
    expect(field(:event_expected_duration_minutes)["value"]).to eq("1.5")
    expect(field(:event_on)["aria-describedby"]).to include("event-date-help", "event_on-errors")
    expect(field(:event_on)["aria-invalid"]).to eq("true")
  end

  it "omits non-event discipline from existing calendar headers while preserving its saved value" do
    plan = create(:training_plan, user: user, discipline: "gravel")
    get root_path
    header = html.at_css("main header")
    expect(header.text).not_to include("Gravel")
    expect(plan.reload.discipline).to eq("gravel")
  end

  it "retains invalid active selections for correction and does not infer missing event discipline from legacy input" do
    preview(inputs(plan_length: "2"))
    expect(response).to have_http_status(:unprocessable_content)
    expect(field(:plan_length).at_css("option[selected]")["value"]).to eq("2")
    expect(field(:plan_length)["aria-invalid"]).to eq("true")
    preview(inputs(goal: "event", event_name: "Trail ride", event_on: "2028-04-30", event_discipline: "unknown"))
    expect(response).to have_http_status(:unprocessable_content)
    expect(field(:event_discipline).at_css("option[selected]")["value"]).to eq("unknown")
    preview(inputs(goal: "event", event_name: "Trail ride", event_on: "2028-04-30", discipline: "gravel"))
    expect(response).to have_http_status(:unprocessable_content)
    expect(field(:event_discipline).at_css("option[selected]")).to be_nil
    expect(field(:event_discipline)["aria-describedby"]).to include("event_discipline-errors")
  end
end
