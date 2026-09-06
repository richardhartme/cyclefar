require "rails_helper"

RSpec.describe "Home", type: :request do
  it "BRD-001 / PLN-001 shows CycleFar navigation and a working no-plan action" do
    get root_path
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("title").text).to eq("CycleFar")
    expect(html.css("nav a").map(&:text)).to eq([ "CycleFar", "Calendar", "Settings" ])
    action = html.css("a").find { |link| link.text == "Create training plan" }
    expect(action["href"]).to eq(new_training_plan_path)
    get action["href"]
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Weekly availability", "Preview plan")
    expect(Nokogiri::HTML(response.body).css("form")).not_to be_empty
  end

  it "uses Monday-first calendar dates" do
    expect(Date.new(2026, 9, 13).beginning_of_week).to eq(Date.new(2026, 9, 7))
    expect(CycleFar::Application.module_parent_name).to eq("CycleFar")
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
