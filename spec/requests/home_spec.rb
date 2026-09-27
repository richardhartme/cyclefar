require "rails_helper"

RSpec.describe "Home", type: :request do
  before { sign_in_as(create(:user)) }

  it "BRD-001 / PLN-001 shows a calendar starting last week and a working no-plan action" do
    travel_to Date.new(2026, 9, 16) do
      get root_path
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css("title").text).to eq("CycleFar")
      expect(html.css("nav a").map(&:text)).to eq([ "CycleFar", "Calendar", "Settings" ])
      weeks = html.css('section[aria-label^="Week of"]')
      expect(weeks.size).to eq(4)
      expect(weeks.first["aria-label"]).to eq("Week of September 07, 2026")
      expect(response.body).to include("Training calendar")
      expect(html.css('aside[aria-label^="Weekly summary for"]')).to be_empty
      expect(html.css('a[aria-label^="Add workout on"]')).to be_empty

      action = html.css("a").find { |link| link.text == "Create training plan" }
      expect(action["href"]).to eq(new_training_plan_path)
      get action["href"]
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Weekly availability", "Preview plan")
      expect(Nokogiri::HTML(response.body).css("form")).not_to be_empty
    end
  end

  it "uses Monday-first calendar dates" do
    expect(Date.new(2026, 9, 13).beginning_of_week).to eq(Date.new(2026, 9, 7))
    expect(CycleFar::Application.module_parent_name).to eq("CycleFar")
  end

  it "CAL-003 charts the summed TSS for every plan week, including empty weeks" do
    plan = create(:training_plan)
    phase = create(:plan_phase, training_plan: plan)
    [ 1, 2 ].each do |offset|
      create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + offset)
    end

    get root_path

    html = Nokogiri::HTML(response.body)
    bars = html.css('ol[aria-label="Weekly TSS"] > li')
    weeks = Planning::CalendarPresenter.new(plan).weeks
    expect(bars.size).to eq(weeks.size)
    expect(bars.first["aria-label"]).to eq("Week of #{weeks.first.starts_on.to_fs(:long)}: 85 TSS")
    expect(bars.last["aria-label"]).to include("0 TSS")
    expect(response.body).not_to include("NaN", "Infinity")
  end

  it "CAL-003 labels recovery weeks without also displaying the plan phase" do
    plan = create(:training_plan)
    create(:plan_phase, training_plan: plan)

    get root_path

    html = Nokogiri::HTML(response.body)
    normal_summary = html.at_css('aside[aria-label="Weekly summary for September 07, 2026"]')
    recovery_summary = html.at_css('aside[aria-label="Weekly summary for September 28, 2026"]')

    expect(normal_summary.at_css(".badge").text).to eq("Base")
    expect(recovery_summary.at_css(".badge").text).to eq("Recovery Week")
  end

  it "provides keyboard navigation and confirmed plan deletion for an active plan" do
    plan = create(:training_plan)
    create(:plan_phase, training_plan: plan)

    get root_path

    html = Nokogiri::HTML(response.body)
    expect(html.at_css('a[href="#main-content"]').text).to eq("Skip to main content")
    expect(html.at_css("main#main-content")["tabindex"]).to eq("-1")
    summary = html.at_css('aside[aria-label^="Weekly summary for"]')
    expect(summary.text).to include("Duration", "Load", "Work")
    delete_form = html.css("form").find { |form| form.at_css("button")&.text == "Delete plan" }
    expect(delete_form["data-turbo-confirm"]).to include("Delete this plan")

    delete training_plan_path
    expect(response).to redirect_to(root_path)
    expect(TrainingPlan.active).not_to exist
    expect(TrainingPlan.find_by(id: plan.id)).to be_nil
  end

  it "archives a plan with completed workouts and labels the control accordingly" do
    plan = create(:training_plan)
    phase = create(:plan_phase, training_plan: plan)
    create(:planned_workout, :completed, training_plan: plan, plan_phase: phase)
    planned = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 2)

    get root_path
    expect(response.body).to include("Archive plan")

    delete training_plan_path
    expect(plan.reload).to be_archived
    expect(PlannedWorkout.exists?(planned.id)).to be(false)
    expect(response).to redirect_to(root_path)
  end
end
