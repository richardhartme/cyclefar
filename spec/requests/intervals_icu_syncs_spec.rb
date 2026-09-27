require "rails_helper"

RSpec.describe "Intervals.icu sync", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as(user) }

  it "ICU-001 shows a manual sync action and reports a missing API key" do
    plan = create(:training_plan, user: user)
    create(:plan_phase, training_plan: plan)

    get root_path
    expect(response.body).to include("Sync next 2 to Intervals.icu")

    post intervals_icu_sync_path
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Add an Intervals.icu API key in Settings before syncing")
  end
end
