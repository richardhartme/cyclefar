require "rails_helper"

RSpec.describe "Plan creation", type: :system do
  let(:user) { create(:user) }

  def sign_in
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: "password"
    click_button "Sign In"
    expect(page).to have_link("Create training plan")
  end

  it "PLN-013 / CAL-001 creates a plan from preview and opens a structured workout" do
    sign_in
    click_link "Create training plan"
    expect(page).to have_current_path(new_training_plan_path)

    choose "Increase FTP"
    fill_in "plan_configuration[ftp_watts]", with: "260"
    %w[Tuesday Thursday Saturday].each { |day| check "Train on #{day}" }
    within("[data-plan-configuration-target='summary']") { expect(page).to have_content("3 training days") }
    click_button "Preview plan"

    expect(page).to have_current_path(preview_training_plan_path)
    expect(page).to have_content("Plan preview")
    click_button "Create plan"

    expect(page).to have_current_path(root_path)
    expect(page).to have_content("Training plan created.")
    expect(page).to have_no_content("FTP Test")

    click_link "Endurance 60 min", match: :first
    expect(page).to have_current_path(%r{\A/planned_workouts/\d+\z})
    expect(page).to have_content("Steps")
    expect(page).to have_css("svg polygon")
  end
end
