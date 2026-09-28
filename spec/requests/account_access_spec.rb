require "rails_helper"

RSpec.describe "Independent rider account access", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.deliveries.clear
    example.run
  ensure
    ActionMailer::Base.deliveries.clear
    ActiveJob::Base.queue_adapter = original_adapter
  end

  it "USR-001 lets a provisioned second rider set a password and sign in to a private calendar" do
    first_rider = create(:user)
    create(:training_plan, user: first_rider)

    second_rider = Accounts::Provision.new(email_address: " Second@Example.com ").call
    expect(second_rider.reload.email_address).to eq("second@example.com")
    expect(second_rider.authenticate("password")).to be_falsey
    message = ActionMailer::Base.deliveries.sole
    expect(message.to).to eq([ "second@example.com" ])
    expect(message.from).to eq([ "no-reply@localhost" ])
    expect(message.subject).to eq("Set or reset your CycleFar password")
    token = reset_token_from(message)

    put password_path(token), params: { password: "new-rider-password", password_confirmation: "new-rider-password" }
    expect(response).to redirect_to(new_session_path)
    sign_in_as(second_rider, password: "new-rider-password")
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create training plan", "second@example.com", "Sign out")
    expect(response.body).not_to include("Change availability")
  end

  it "USR-001 clears the signed-out rider's preview draft even if they sign in again" do
    rider = create(:user)
    sign_in_as(rider)
    post preview_training_plan_path, params: { plan_configuration: plan_configuration }
    expect(response).to have_http_status(:ok)

    delete session_path
    expect(rider.sessions.count).to eq(0)
    sign_in_as(rider)
    expect { post training_plan_path }.not_to change(TrainingPlan, :count)
    expect(response).to redirect_to(new_training_plan_path)
  end

  it "USR-001 delivers reset mail without exposing whether the account exists and invalidates old sessions" do
    rider = create(:user)
    sign_in_as(rider)

    perform_enqueued_jobs do
      post passwords_path, params: { email_address: " #{rider.email_address.upcase} " }
    end
    known_response = [ response.status, response.location ]
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    message = ActionMailer::Base.deliveries.sole
    expect(message.to).to eq([ rider.email_address ])
    token = reset_token_from(message)
    follow_redirect!
    known_notice = Nokogiri::HTML(response.body).at_css('[role="status"]').text.strip

    perform_enqueued_jobs do
      post passwords_path, params: { email_address: "missing@example.com" }
    end
    expect([ response.status, response.location ]).to eq(known_response)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    follow_redirect!
    expect(Nokogiri::HTML(response.body).at_css('[role="status"]').text.strip).to eq(known_notice)

    put password_path(token), params: { password: "replacement-password", password_confirmation: "replacement-password" }
    expect(rider.sessions.count).to eq(0)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  def plan_configuration
    {
      goal: "increase_ftp", discipline: "road", starts_on: "2026-09-07", duration_mode: "preset", duration_months: "3",
      ftp_watts: "260", include_base: "1", progression_mode: "continuous",
      availability: { "1" => { weekday: "1", enabled: "1", duration_minutes: "60", intent: "intervals" } }
    }
  end

  def reset_token_from(message)
    link = message.text_part.body.decoded.lines.map(&:strip).find { |line| line.start_with?("http://example.com/passwords/") }
    expect(link).to be_present
    URI(link).path.split("/")[2]
  end
end
